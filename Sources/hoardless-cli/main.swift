import Foundation
import HoardlessCore

// Read-only scan printed as JSON. Locations that would trigger a macOS permission prompt are listed, not read.
// Usage: hoardless-cli [rules_dir]

let rulesDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : RuleLoader.bundledRulesDirectory()
guard let rulesDir else {
    FileHandle.standardError.write("No rules folder found\n".data(using: .utf8)!)
    exit(2)
}

let rules = try RuleLoader.load(from: rulesDir)
let plan = ScanPlan.make(rules: rules, policy: PathPolicy(), environment: ProcessInfo.processInfo.environment)
let results = await ScanPlan.scanAutomatic(plan)

func describe(_ state: LocationState) -> [String: Any] {
    switch state {
    case .measured(let u): return ["state": "measured", "bytes": u.bytes, "files": u.files, "symlinks": u.symlinks, "unreadable": u.unreadable]
    case .missing: return ["state": "missing"]
    case .needsPermission: return ["state": "needs_permission"]
    case .notScanned, .scanning: return ["state": "not_scanned"]
    case .failed(let why): return ["state": "failed", "reason": why]
    }
}

let output: [[String: Any]] = results.map { r in
    [
        "id": r.rule.id,
        "safety": r.rule.safety.rawValue,
        "bytes": r.bytes,
        "locations": r.locations.map { loc in ["display": loc.display, "path": loc.url.path].merging(describe(r.states[loc.id] ?? .notScanned)) { a, _ in a } },
        "rejected": r.rejected.map { ["display": $0.display, "path": $0.path, "reason": $0.reason] },
    ]
}
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
