import AppKit
import HoardlessCore

/// Holds the scan for the window. Version 0.1 is read-only: it measures, reveals in Finder and copies text.
@MainActor
final class AppModel: ObservableObject {
    enum Phase { case idle, scanning, done }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var results: [RuleResult] = []
    @Published private(set) var currentApp: String?
    @Published private(set) var loadError: String?
    @Published var openCategory: Rule.Category?

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

    func toggleScan() {
        if phase == .scanning {
            scanTask?.cancel()
            return
        }
        guard working == nil else { return }  // never rescan while a file is being moved
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
        let plan = ScanPlan.make(rules: rules, policy: policy, environment: ProcessInfo.processInfo.environment)
        results = plan.map(keepAllowedScans)
        phase = .scanning
        let started = Date()
        for await event in ScanPlan.scanEvents(results) {
            guard let i = results.firstIndex(where: { $0.id == event.ruleID }) else { continue }
            results[i].states[event.locationID] = event.state
            currentApp = results[i].rule.app
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

    // MARK: trash and move (the only actions that change files; all go through FileActions)

    enum PendingAction: Identifiable {
        case trash(Location, RuleResult)
        case move(Location, RuleResult, URL)

        var id: String {
            switch self {
            case .trash(let loc, _): return "trash:" + loc.id
            case .move(let loc, _, let dest): return "move:" + loc.id + "->" + dest.path
            }
        }
        var location: Location {
            switch self {
            case .trash(let loc, _), .move(let loc, _, _): return loc
            }
        }
        var result: RuleResult {
            switch self {
            case .trash(_, let r), .move(_, let r, _): return r
            }
        }
    }

    @Published var pending: PendingAction?
    @Published private(set) var working: String?
    @Published private(set) var lastRecord: ActionRecord?
    @Published var actionError: String?
    private let actions = FileActions()

    func canAct(_ location: Location, in result: RuleResult) -> Bool {
        phase != .scanning && working == nil && actions.canAct(location, in: result)
    }

    func askTrash(_ location: Location, in result: RuleResult) {
        pending = .trash(location, result)
    }

    func askMove(_ location: Location, in result: RuleResult) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = Strings(chinese: chinese).chooseFolder
        panel.message = Strings(chinese: chinese).chooseFolderMessage
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        pending = .move(location, result, folder)
    }

    func confirmPending() {
        guard let action = pending else { return }
        pending = nil
        guard working == nil, phase != .scanning else { return }
        // Act on the latest scan of this rule, never on the copy captured when the dialog opened.
        guard let current = results.first(where: { $0.id == action.result.id }) else { return }
        working = action.location.id
        actionError = nil
        let actions = self.actions
        Task {
            let outcome: Result<ActionRecord, Error> = await Task.detached(priority: .userInitiated) {
                switch action {
                case .trash(let loc, _): return Result { try actions.trash(loc, of: current) }
                case .move(let loc, _, let dest): return Result { try actions.move(loc, of: current, to: dest) }
                }
            }.value
            working = nil
            switch outcome {
            case .success(let record):
                update(record.ruleID, record.locationID, .missing)
                lastRecord = record
            case .failure(let error):
                actionError = Strings(chinese: chinese).actionFailed(error)
            }
        }
    }

    func undoLast() {
        guard working == nil, phase != .scanning, let record = lastRecord else { return }
        working = record.locationID
        actionError = nil
        let actions = self.actions
        Task {
            let outcome = await Task.detached { Result { try actions.undo(record) } }.value
            working = nil
            switch outcome {
            case .success:
                if lastRecord?.id == record.id { lastRecord = nil }
                if let r = results.first(where: { $0.id == record.ruleID }), let loc = r.locations.first(where: { $0.id == record.locationID }) {
                    await measure(loc, ruleID: r.id)
                }
            case .failure(let error):
                actionError = Strings(chinese: chinese).actionFailed(error)
            }
        }
    }

    func dismissRecord() { lastRecord = nil }

    /// The exact folder a move would land in, for the confirmation dialog.
    func plannedTarget(_ action: PendingAction) -> URL? {
        guard case .move(let loc, let result, let folder) = action else { return nil }
        return actions.plannedTarget(for: loc, of: result, in: folder)
    }

    func reveal(_ location: Location) {
        NSWorkspace.shared.activateFileViewerSelecting([location.url])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
