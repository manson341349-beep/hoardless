import AppKit
import HoardlessCore

/// Holds the scan for the window, the page shown, what the user ticked, and Trash / Move / Undo.
@MainActor
final class AppModel: ObservableObject {
    enum Phase { case idle, scanning, done }

    /// What the window shows next to the sidebar.
    enum Screen: Hashable {
        case overview
        case category(Rule.Category)
        case duplicates
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var results: [RuleResult] = []
    @Published private(set) var currentApp: String?
    @Published private(set) var loadError: String?

    // MARK: navigation (sidebar, plus Back / Forward through pages already seen)

    @Published private(set) var screen: Screen = .overview
    @Published private(set) var backStack: [Screen] = []
    @Published private(set) var forwardStack: [Screen] = []

    func show(_ next: Screen) {
        guard next != screen, pending == nil else { return }
        backStack.append(screen)
        forwardStack.removeAll()
        screen = next
    }

    func goBack() {
        guard pending == nil, let previous = backStack.popLast() else { return }
        forwardStack.append(screen)
        screen = previous
    }

    func goForward() {
        guard pending == nil, let next = forwardStack.popLast() else { return }
        backStack.append(screen)
        screen = next
    }
    @Published var showingDuplicates = false

    enum Language: String, CaseIterable { case system, chinese, english }

    /// The user's pick in the window's language switch, remembered between launches.
    @Published var language: Language = Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "language")
            // The menu bar's own items (About, Hide, Quit…) come from macOS and follow this from the next launch.
            switch language {
            case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            case .chinese: UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
            case .english: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            }
        }
    }

    var chinese: Bool {
        switch language {
        case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        case .chinese: return true
        case .english: return false
        }
    }
    private let policy = PathPolicy()
    private var scanTask: Task<Void, Never>?

    var summaries: [Rule.Category: CategorySummary] { Summary.byCategory(results) }
    var totalBytes: Int64 { results.reduce(0) { $0 + $1.bytes } }
    var actionableBytes: Int64 { summaries.values.reduce(0) { $0 + $1.actionableBytes } }
    var protectedBytes: Int64 { summaries.values.reduce(0) { $0 + $1.protectedBytes } }

    /// Settings › General: scan when the app opens (read-only, so on by default).
    @Published var autoScan: Bool = UserDefaults.standard.object(forKey: "autoScan") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoScan, forKey: "autoScan") }
    }
    private var launched = false

    /// Called when the window first appears.
    func appeared() {
        guard !launched else { return }
        launched = true
        if autoScan { toggleScan() }
    }

    func toggleScan() {
        if phase == .scanning {
            scanTask?.cancel()
            return
        }
        guard !working else { return }  // never rescan while a file is being moved
        scanTask = Task { await scan() }
    }

    private func scan() async {
        guard let dir = RuleLoader.bundledRulesDirectory() else {
            loadError = "rules folder not found"
            return
        }
        let rules: [Rule]
        do { rules = try RuleLoader.load(from: dir) } catch {
            loadError = error.localizedDescription
            return
        }
        loadError = nil
        selection = []  // ticks belong to the previous scan
        let plan = ScanPlan.make(rules: rules, policy: policy, environment: ProcessInfo.processInfo.environment)
        results = plan.map(keepAllowedScans)
        phase = .scanning
        let started = Date()
        for await event in ScanPlan.scanEvents(results) {
            guard let i = results.firstIndex(where: { $0.id == event.ruleID }) else { continue }
            results[i].states[event.locationID] = event.state
            currentApp = results[i].rule.app
        }
        // Folders the user allowed earlier keep their old size only until here: measure them again (no new prompt),
        // so nothing can be acted on with a size from an older scan.
        for r in results {
            for loc in r.locations where loc.needsPermission {
                guard !Task.isCancelled, case .measured = r.states[loc.id] ?? .notScanned else { continue }
                currentApp = r.rule.app
                await measure(loc, ruleID: r.id)
            }
        }
        // Keep the scan animation on screen long enough to read, even when the disk answers instantly.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 1.2, !Task.isCancelled { try? await Task.sleep(for: .seconds(1.2 - elapsed)) }
        currentApp = nil
        phase = Task.isCancelled ? .idle : .done
    }

    /// Sizes the user already allowed stay, so a rescan does not ask again.
    private func keepAllowedScans(_ fresh: RuleResult) -> RuleResult {
        guard let old = results.first(where: { $0.id == fresh.id }) else { return fresh }
        var r = fresh
        for loc in r.locations where loc.needsPermission {
            if let state = old.states[loc.id], case .measured = state { r.states[loc.id] = state }
        }
        return r
    }

    /// Measures one location that needs permission; macOS may show its own prompt now.
    func measure(_ location: Location, ruleID: String) async {
        update(ruleID, location.id, .scanning)
        let url = location.url
        let state = await Task.detached(priority: .userInitiated) { Scanner.measure(url) }.value
        update(ruleID, location.id, state)
    }

    private func update(_ ruleID: String, _ locationID: String, _ state: LocationState) {
        guard let i = results.firstIndex(where: { $0.id == ruleID }) else { return }
        results[i].states[locationID] = state
    }

    // MARK: picking, trash and move (files only change through FileActions)

    /// One ticked location and the rule it belongs to.
    struct Item: Identifiable {
        let location: Location
        let result: RuleResult
        var id: String { location.id }
        var bytes: Int64 { result.states[location.id]?.bytes ?? 0 }
        var batchItem: BatchItem { BatchItem(ruleID: result.id, location: location) }
    }

    enum PendingAction: Identifiable {
        case trash([Item])
        case move([Item], URL)

        var id: String {
            switch self {
            case .trash(let items): return "trash:" + items.map(\.id).joined(separator: "|")
            case .move(let items, let dest): return "move:" + items.map(\.id).joined(separator: "|") + "->" + dest.path
            }
        }
        var items: [Item] {
            switch self {
            case .trash(let items), .move(let items, _): return items
            }
        }
    }

    /// Location ids the user ticked. Nothing is ever ticked for them.
    @Published private(set) var selection: Set<String> = []
    @Published var pending: PendingAction?
    @Published private(set) var working = false
    @Published private(set) var lastRecords: [ActionRecord] = []
    @Published var actionError: String?
    private let actions = FileActions()

    func canAct(_ location: Location, in result: RuleResult) -> Bool {
        phase != .scanning && !working && actions.canAct(location, in: result)
    }

    /// The locations of a rule that may be trashed or moved right now.
    func actionable(_ result: RuleResult) -> [Location] {
        busy ? [] : actions.actionable(result, among: results)
    }

    /// Whether the rule has locations that could be acted on once no scan or action is running (for showing a
    /// disabled tick box instead of a lock while busy).
    func couldAct(_ result: RuleResult) -> Bool {
        !actions.actionable(result, among: results).isEmpty
    }

    var busy: Bool { working || phase == .scanning }

    func isSelected(_ result: RuleResult) -> Bool {
        let ids = actionable(result).map(\.id)
        return !ids.isEmpty && ids.allSatisfy(selection.contains)
    }

    /// Ticks or unticks every location of the rule that may be acted on.
    func toggle(_ result: RuleResult) {
        let ids = Set(actionable(result).map(\.id))
        guard !ids.isEmpty else { return }
        if ids.isSubset(of: selection) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    /// Ticked locations on one category's page, re-checked against the latest scan.
    func selectedItems(in category: Rule.Category) -> [Item] {
        guard !busy else { return [] }
        let page = results.filter { $0.rule.category == category }
        return actions.items(for: selection, in: page).compactMap { item in
            page.first(where: { $0.id == item.ruleID }).map { Item(location: item.location, result: $0) }
        }
    }

    func clearSelection() { selection = [] }

    func askTrash(_ items: [Item]) {
        guard !items.isEmpty else { return }
        pending = .trash(items)
    }

    func askMove(_ items: [Item]) {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = Strings(chinese: chinese).chooseFolder
        panel.message = Strings(chinese: chinese).chooseFolderMessage
        panel.directoryURL = startFolderForMove()
        let batch = items.map(\.batchItem), current = results, actions = self.actions
        let t = Strings(chinese: chinese)
        let refusal = { (folder: URL) -> String in
            t.actionFailed(ActionError.badDestination(actions.isInsideAppData(folder, among: current) ? .insideAppData : .notAllowedPlace))
        }
        // Checked when "Move here" is clicked, so a folder that can't be used keeps the panel open with the reason.
        let validator = MoveFolderValidator { actions.plannedTargets(batch, in: current, folder: $0) == nil ? refusal($0) : nil }
        panel.delegate = validator
        let answer = withExtendedLifetime(validator) { panel.runModal() }
        guard answer == .OK, let folder = panel.url else { return }
        guard actions.plannedTargets(batch, in: current, folder: folder) != nil else {
            actionError = refusal(folder)
            return
        }
        UserDefaults.standard.set(folder.path, forKey: "lastMoveFolder")
        pending = .move(items, folder)
    }

    /// The folder the last move went to if it still exists, otherwise Documents (never the home folder itself, which
    /// can't be used).
    private func startFolderForMove() -> URL {
        if let last = UserDefaults.standard.string(forKey: "lastMoveFolder") {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: last, isDirectory: &isDir), isDir.boolValue { return URL(fileURLWithPath: last) }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    }

    /// Acts on each item in turn. Each one is checked again by FileActions right before it changes; one that fails
    /// is reported and the rest go on.
    func confirmPending() {
        guard let action = pending else { return }
        pending = nil
        guard !working, phase != .scanning else { return }
        let current = results
        let items = action.items.map(\.batchItem)
        let kind: BatchKind
        switch action {
        case .trash: kind = .trash
        case .move(_, let folder): kind = .move(to: folder)
        }
        working = true
        actionError = nil
        let actions = self.actions
        let t = Strings(chinese: chinese)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { actions.run(kind, items, in: current) }.value
            working = false
            for record in outcome.records {
                update(record.ruleID, record.locationID, .missing)
                selection.remove(record.locationID)
            }
            lastRecords = UndoHistory.after(outcome, previous: lastRecords)
            let failures = outcome.failures.map { "\($0.location.display): \(t.actionFailed($0.error))" }
            if !failures.isEmpty { actionError = failures.joined(separator: "\n") }
        }
    }

    func undoLast() {
        guard !working, phase != .scanning, !lastRecords.isEmpty else { return }
        let records = lastRecords
        working = true
        actionError = nil
        let actions = self.actions
        let t = Strings(chinese: chinese)
        Task {
            let outcome = await Task.detached { actions.undoAll(records) }.value
            for record in outcome.restored {
                if let r = results.first(where: { $0.id == record.ruleID }), let loc = r.locations.first(where: { $0.id == record.locationID }) {
                    await measure(loc, ruleID: r.id)
                }
            }
            let failures = outcome.failed.map { t.undoFailed($0.record.original.path, now: $0.record.now.path, t.actionFailed($0.error)) }
            // Still busy until here, so no other action can start while the restored folders are measured.
            lastRecords = UndoHistory.after(outcome)
            working = false
            if !failures.isEmpty { actionError = failures.joined(separator: "\n") }
        }
    }

    func dismissRecords() { lastRecords = [] }

    /// The exact folder a move would land in for one item, for the confirmation sheet.
    func plannedTarget(_ item: Item, in folder: URL) -> URL? {
        actions.plannedTarget(for: item.location, of: item.result, in: folder)
    }

    /// The folder is in iCloud Drive (for example a synced Desktop or Documents), so whatever goes in is uploaded.
    func isInICloud(_ folder: URL) -> Bool {
        (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }

    func reveal(_ location: Location) {
        NSWorkspace.shared.activateFileViewerSelecting([location.url])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Refuses a folder in the Move panel itself: the panel shows the reason and stays open.
private final class MoveFolderValidator: NSObject, NSOpenSavePanelDelegate {
    private let problem: (URL) -> String?

    init(problem: @escaping (URL) -> String?) {
        self.problem = problem
    }

    func panel(_ sender: Any, validate url: URL) throws {
        if let message = problem(url) {
            throw NSError(domain: "Hoardless", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
