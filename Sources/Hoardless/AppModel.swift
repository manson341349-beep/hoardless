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
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
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
        result.locations.filter { canAct($0, in: result) }
    }

    /// Whether the rule has locations that could be acted on once no scan or action is running (for showing a
    /// disabled tick box instead of a lock while busy).
    func couldAct(_ result: RuleResult) -> Bool {
        result.locations.contains { actions.canAct($0, in: result) }
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
        results.filter { $0.rule.category == category }.flatMap { r in
            actionable(r).filter { selection.contains($0.id) }.map { Item(location: $0, result: r) }
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
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard items.allSatisfy({ plannedTarget($0, in: folder) != nil }) else {
            actionError = Strings(chinese: chinese).actionFailed(ActionError.badDestination(.notAllowedPlace))
            return
        }
        pending = .move(items, folder)
    }

    /// Acts on each item in turn. Each one is checked again by FileActions right before it changes; one that fails
    /// is reported and the rest go on.
    func confirmPending() {
        guard let action = pending else { return }
        pending = nil
        guard !working, phase != .scanning else { return }
        let current = results
        let jobs: [(Location, RuleResult)] = action.items.compactMap { item in
            current.first(where: { $0.id == item.result.id }).map { (item.location, $0) }
        }
        working = true
        actionError = nil
        let actions = self.actions
        let t = Strings(chinese: chinese)
        Task {
            let outcomes: [(Location, RuleResult, Result<ActionRecord, Error>)] = await Task.detached(priority: .userInitiated) {
                jobs.map { loc, result in
                    switch action {
                    case .trash: return (loc, result, Result { try actions.trash(loc, of: result) })
                    case .move(_, let dest): return (loc, result, Result { try actions.move(loc, of: result, to: dest) })
                    }
                }
            }.value
            working = false
            var records: [ActionRecord] = [], failures: [String] = []
            for (loc, _, outcome) in outcomes {
                switch outcome {
                case .success(let record):
                    update(record.ruleID, record.locationID, .missing)
                    selection.remove(record.locationID)
                    records.append(record)
                case .failure(let error):
                    failures.append("\(loc.display): \(t.actionFailed(error))")
                }
            }
            if !records.isEmpty { lastRecords = records }
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
            let outcomes = await Task.detached { records.reversed().map { r in (r, Result { try actions.undo(r) }) } }.value
            var failures: [String] = [], notUndone: [ActionRecord] = []
            for (record, outcome) in outcomes {
                switch outcome {
                case .success:
                    if let r = results.first(where: { $0.id == record.ruleID }), let loc = r.locations.first(where: { $0.id == record.locationID }) {
                        await measure(loc, ruleID: r.id)
                    }
                case .failure(let error):
                    notUndone.append(record)
                    failures.append(t.undoFailed(record.original.path, now: record.now.path, t.actionFailed(error)))
                }
            }
            // Still busy until here, so no other action can start while the restored folders are measured.
            lastRecords = notUndone.reversed()
            working = false
            if !failures.isEmpty { actionError = failures.joined(separator: "\n") }
        }
    }

    func dismissRecords() { lastRecords = [] }

    /// The exact folder a move would land in for one item, for the confirmation sheet.
    func plannedTarget(_ item: Item, in folder: URL) -> URL? {
        actions.plannedTarget(for: item.location, of: item.result, in: folder)
    }

    func reveal(_ location: Location) {
        NSWorkspace.shared.activateFileViewerSelecting([location.url])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
