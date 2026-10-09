import AppKit
import HoardlessCore

/// The duplicates screen: which folders to search, the search itself, what the user picked, and Trash/Undo.
/// Files only change through FileActions.trashDuplicates and FileActions.undo.
@MainActor
final class DuplicateModel: ObservableObject {
    enum Phase { case setup, searching, done }

    struct Folder: Identifiable, Hashable {
        let url: URL
        let suggested: Bool
        var on: Bool
        var id: String { url.path }
    }

    @Published var folders: [Folder] = []
    @Published private(set) var phase: Phase = .setup
    @Published private(set) var filesSeen = 0
    @Published private(set) var bytesDone: Int64 = 0
    @Published private(set) var bytesTotal: Int64 = 0
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var skipped = DuplicateFinder.Skipped()
    @Published private(set) var selection: Set<String> = []
    @Published var showViewOnlyGroups = false
    @Published var confirming = false
    @Published private(set) var working = false
    @Published private(set) var lastRecords: [ActionRecord] = []
    @Published var problem: String?

    private let policy = PathPolicy()
    private let actions = FileActions()
    private var search: DuplicateSearch?
    private var task: Task<Void, Never>?
    private var chinese = false
    /// Trashed copies and the group they came from, so Undo can show them again.
    private var removed: [String: (group: String, file: DuplicateFile)] = [:]
    /// Groups that dropped off the list because fewer than two copies were left.
    private var droppedGroups: [String: DuplicateGroup] = [:]

    init() {
        let home = policy.home
        let defaultsOn: Set<String> = ["Downloads", "Movies"]
        folders = ["Downloads", "Movies", "Desktop", "Documents", "Pictures"].compactMap { name in
            let url = home.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Folder(url: url, suggested: true, on: defaultsOn.contains(name))
        }
    }

    // MARK: folders

    func addFolders(_ t: Strings) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = t.dupAddPrompt
        panel.directoryURL = policy.home
        guard panel.runModal() == .OK else { return }
        var refused: [String] = []
        for url in panel.urls {
            switch DuplicateSearch.checkRoot(url, policy: policy) {
            case .success(let real):
                if let i = folders.firstIndex(where: { $0.url == real }) { folders[i].on = true } else {
                    folders.append(Folder(url: real, suggested: false, on: true))
                }
            case .failure(let why):
                refused.append(t.dupRefused(url.path, why))
            }
        }
        problem = refused.isEmpty ? nil : refused.joined(separator: "\n")
    }

    func removeFolder(_ folder: Folder) { folders.removeAll { $0.id == folder.id } }

    func display(_ url: URL) -> String { policy.tilde(url) }

    // MARK: search

    var canStart: Bool { phase != .searching && !working && folders.contains(where: \.on) }

    func start(chinese: Bool) {
        guard canStart else { return }
        problem = nil
        self.chinese = chinese
        let rules = RuleLoader.bundledRulesDirectory().flatMap { try? RuleLoader.load(from: $0) } ?? []
        let environment = ProcessInfo.processInfo.environment
        let locations = rules.flatMap { policy.locations(for: $0, environment: environment).accepted }
        let search = DuplicateSearch(roots: folders.filter(\.on).map(\.url),
                                     appFolders: DuplicateSearch.appFolders(for: locations, policy: policy), policy: policy)
        self.search = search
        if !search.refused.isEmpty {
            let t = Strings(chinese: chinese)
            problem = search.refused.map { t.dupRefused(display($0.url), $0.problem) }.joined(separator: "\n")
        }
        guard !search.roots.isEmpty else { return }
        groups = []
        selection = []
        lastRecords = []
        removed = [:]
        droppedGroups = [:]
        filesSeen = 0
        bytesDone = 0
        bytesTotal = 0
        phase = .searching
        task = Task {
            for await event in DuplicateFinder.events(search) {
                switch event {
                case .listing(let n): filesSeen = n
                case .comparing(let done, let total): bytesDone = done; bytesTotal = total
                case .finished(let found, let skipped):
                    groups = found
                    self.skipped = skipped
                    phase = .done
                }
            }
            if phase == .searching { phase = .setup }  // stopped
        }
    }

    func stop() { task?.cancel() }

    func backToSetup() {
        guard !working else { return }
        phase = .setup
        groups = []
        selection = []
        lastRecords = []
    }

    // MARK: picking

    var visibleGroups: [DuplicateGroup] {
        showViewOnlyGroups ? groups : groups.filter { g in g.files.contains { $0.viewOnly == nil } }
    }
    var viewOnlyGroupCount: Int { groups.count - groups.filter { g in g.files.contains { $0.viewOnly == nil } }.count }
    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }
    var selectedBytes: Int64 {
        groups.reduce(0) { sum, g in sum + g.files.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.freeable } }
    }

    func canToggle(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        !working && group.canSelect(file, alreadySelected: selection)
    }

    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        guard canToggle(file, in: group) else { return }
        if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
    }

    /// Picks every copy in the group except the suggested keeper. Only when the user clicks it.
    func keepOne(_ group: DuplicateGroup) {
        guard !working else { return }
        let others = selection.subtracting(group.files.map(\.id))
        selection = others.union(group.keepingOne(current: selection))
    }

    func keepOneEverywhere() { for g in visibleGroups { keepOne(g) } }

    func clearSelection() { selection = [] }

    func isSelected(_ file: DuplicateFile) -> Bool { selection.contains(file.id) }

    var selectedFiles: [DuplicateFile] { groups.flatMap(\.files).filter { selection.contains($0.id) } }

    // MARK: trash and undo

    func confirmTrash(_ t: Strings) {
        confirming = false
        guard !working, let search, !selection.isEmpty else { return }
        working = true
        problem = nil
        let picked = selection, groups = self.groups, actions = self.actions
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                actions.trashDuplicates(picked, in: groups, search: search)
            }.value
            working = false
            let gone = Set(outcome.records.map(\.locationID))
            for g in self.groups {
                for f in g.files where gone.contains(f.id) { removed[f.id] = (g.id, f) }
            }
            self.groups = self.groups.compactMap { g in
                var g = g
                g.files.removeAll { gone.contains($0.id) }
                if g.files.count > 1 { return g }
                droppedGroups[g.id] = g
                return nil
            }
            selection.subtract(picked)
            lastRecords = outcome.records
            if !outcome.failures.isEmpty {
                problem = outcome.failures.map { "\(display(URL(fileURLWithPath: $0.path))): \(t.actionFailed($0.error))" }.joined(separator: "\n")
            }
        }
    }

    func undo(_ t: Strings) {
        guard !working, !lastRecords.isEmpty else { return }
        working = true
        problem = nil
        let records = lastRecords, actions = self.actions
        Task {
            let results = await Task.detached { records.map { r in (r, Result { try actions.undo(r) }) } }.value
            working = false
            var failures: [String] = []
            for (record, result) in results {
                switch result {
                case .success:
                    // Moving it back changes its status-change time; take the new times so it can be picked again.
                    guard let (groupID, old) = removed.removeValue(forKey: record.locationID), let file = old.refreshed() else { continue }
                    if !groups.contains(where: { $0.id == groupID }), let dropped = droppedGroups.removeValue(forKey: groupID) {
                        groups.append(dropped)
                    }
                    if let i = groups.firstIndex(where: { $0.id == groupID }) {
                        groups[i].files.append(file)
                        groups[i].files.sort { $0.url.path < $1.url.path }
                    }
                case .failure(let error):
                    failures.append("\(display(record.original)): \(t.actionFailed(error))")
                }
            }
            groups = groups.filter { $0.files.count > 1 }.sorted { ($0.wasted, $0.size) > ($1.wasted, $1.size) }
            lastRecords = []
            if !failures.isEmpty { problem = failures.joined(separator: "\n") }
        }
    }

    func dismissRecords() { lastRecords = [] }

    func reveal(_ file: DuplicateFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
}
