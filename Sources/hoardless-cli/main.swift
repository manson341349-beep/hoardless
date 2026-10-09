import Foundation
import HoardlessCore

// Read-only scan printed as JSON. Locations that would trigger a macOS permission prompt are listed, not read.
// Usage: hoardless-cli [rules_dir]
//        hoardless-cli duplicates <folder>...   (read-only duplicate search; rule folders from the bundled rules)

if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "duplicates" {
    let policy = PathPolicy()
    let folders = CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    for f in folders {
        if case .failure(let why) = DuplicateSearch.checkRoot(f, policy: policy) {
            FileHandle.standardError.write("refused \(f.path): \(why)\n".data(using: .utf8)!)
        }
    }
    let rules = RuleLoader.bundledRulesDirectory().flatMap { try? RuleLoader.load(from: $0) } ?? []
    let locations = rules.flatMap { policy.locations(for: $0, environment: ProcessInfo.processInfo.environment).accepted }
    let search = DuplicateSearch(roots: folders, appFolders: DuplicateSearch.appFolders(for: locations, policy: policy), policy: policy)
    guard let (groups, skipped) = DuplicateFinder.find(search) else { exit(1) }
    let out: [String: Any] = [
        "roots": search.roots.map(\.path),
        "groups": groups.map { g in
            ["size": g.size, "wasted": g.wasted, "digest": String(g.digest.prefix(12)),
             "files": g.files.map { f in ["path": f.url.path, "freeable": f.freeable, "view_only": f.viewOnly.map { "\($0)" } ?? ""] }] as [String: Any]
        },
        "wasted_total": groups.reduce(Int64(0)) { $0 + $1.wasted },
        "skipped_not_downloaded": skipped.notDownloaded, "skipped_unreadable": skipped.unreadable,
    ]
    print(String(data: try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    exit(0)
}

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
