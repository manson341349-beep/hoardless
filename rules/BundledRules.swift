import Foundation

// Makes rules/apps a package resource without copying or linking it: the rule files stay where contributors edit
// them, and `swift run` / `swift test` find them here. A built .app gets its own copy (scripts/build_app.sh).
public enum BundledRules {
    /// The folder of rule files bundled with the package.
    public static var directory: URL? { Bundle.module.url(forResource: "apps", withExtension: nil) }
}
