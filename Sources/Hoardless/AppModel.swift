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

    func reveal(_ location: Location) {
        NSWorkspace.shared.activateFileViewerSelecting([location.url])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
