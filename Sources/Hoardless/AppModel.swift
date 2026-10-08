import AppKit
import HoardlessCore

/// Holds the scan for the window. Version 0.1 is read-only: it measures, reveals in Finder and copies text.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var results: [RuleResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var loadError: String?

    let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    private let policy = PathPolicy()

    var totalBytes: Int64 { results.reduce(0) { $0 + $1.bytes } }

    func rescan() async {
        guard !isScanning else { return }
        guard let dir = RuleLoader.bundledRulesDirectory() else {
            loadError = "rules folder not found"
            return
        }
        do {
            let rules = try RuleLoader.load(from: dir)
            let plan = ScanPlan.make(rules: rules, policy: policy, environment: ProcessInfo.processInfo.environment)
            // Keep sizes the user already allowed, so a rescan does not ask again.
            results = plan.map { carryOverPermissionScans(into: $0) }
            isScanning = true
            results = await ScanPlan.scanAutomatic(results)
            isScanning = false
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            isScanning = false
        }
    }

    private func carryOverPermissionScans(into fresh: RuleResult) -> RuleResult {
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
