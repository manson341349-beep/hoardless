import Foundation

public struct Usage: Sendable, Hashable {
    /// Space on disk (allocated size), each hard-linked file counted once — the same way `du` counts.
    public var bytes: Int64 = 0
    public var files: Int = 0
    /// Symlinks found inside; never followed, never counted.
    public var symlinks: Int = 0
    /// Items macOS would not let us read.
    public var unreadable: Int = 0
}

public enum LocationState: Sendable, Hashable {
    case notScanned
    case needsPermission
    case scanning
    case missing
    case measured(Usage)
    case failed(String)

    public var bytes: Int64 {
        if case .measured(let usage) = self { return usage.bytes }
        return 0
    }
}

/// Read-only: looks at sizes, never opens, changes, moves or deletes anything.
public enum Scanner {
    private static let keys: [URLResourceKey] = [
        .isSymbolicLinkKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileResourceIdentifierKey,
    ]

    public static func measure(_ url: URL, isCancelled: @Sendable () -> Bool = { false }) -> LocationState {
        let fm = FileManager.default
        guard let top = try? url.resourceValues(forKeys: Set(keys + [.isDirectoryKey])) else { return .missing }
        if top.isSymbolicLink == true { return .failed("is a symlink") }  // PathPolicy resolves links first
        var usage = Usage()
        var seen = Set<AnyHashable>()

        func add(_ values: URLResourceValues) {
            if let id = values.fileResourceIdentifier as? NSObject {
                guard seen.insert(AnyHashable(id)).inserted else { return }
            }
            usage.bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            usage.files += 1
        }

        if top.isDirectory != true {
            if top.isRegularFile == true { add(top) }
            return .measured(usage)
        }
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                         errorHandler: { _, _ in usage.unreadable += 1; return true })
        else { return .failed("cannot open") }
        for case let item as URL in walker {
            if isCancelled() { return .notScanned }
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { usage.unreadable += 1; continue }
            if values.isSymbolicLink == true { usage.symlinks += 1; continue }
            if values.isRegularFile == true { add(values) }
        }
        return .measured(usage)
    }
}

/// One rule with the state of each of its locations.
public struct RuleResult: Sendable, Identifiable {
    public let rule: Rule
    public var locations: [Location]
    public var rejected: [RejectedLocation]
    public var states: [String: LocationState]  // keyed by Location.id

    public var id: String { rule.id }
    public var bytes: Int64 { locations.reduce(0) { $0 + (states[$1.id]?.bytes ?? 0) } }
    public var isPresent: Bool {
        locations.contains { loc in
            switch states[loc.id] ?? .notScanned {
            case .missing: return false
            default: return true
            }
        }
    }
}

public enum ScanPlan {
    /// Locations for every rule. Ones that would trigger a macOS permission prompt start as .needsPermission
    /// and are only measured when the user asks.
    public static func make(rules: [Rule], policy: PathPolicy, environment: [String: String]) -> [RuleResult] {
        rules.map { rule in
            let (accepted, rejected) = policy.locations(for: rule, environment: environment)
            var states: [String: LocationState] = [:]
            for loc in accepted { states[loc.id] = loc.needsPermission ? .needsPermission : .notScanned }
            return RuleResult(rule: rule, locations: accepted, rejected: rejected, states: states)
        }
    }

    /// One location finished measuring.
    public struct Event: Sendable {
        public let ruleID: String
        public let locationID: String
        public let state: LocationState
    }

    /// Measures every location that does not need permission, a few at a time, reporting each one as it finishes.
    /// Cancelling the consuming task stops the scan.
    public static func scanEvents(_ results: [RuleResult]) -> AsyncStream<Event> {
        let jobs = results.flatMap { r in r.locations.filter { !$0.needsPermission }.map { (r.id, $0) } }
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: Event.self) { group in
                    var iterator = jobs.makeIterator()
                    func next() -> Bool {
                        guard let (ruleID, loc) = iterator.next() else { return false }
                        group.addTask {
                            Event(ruleID: ruleID, locationID: loc.id,
                                  state: Scanner.measure(loc.url, isCancelled: { Task.isCancelled }))
                        }
                        return true
                    }
                    for _ in 0..<4 where next() {}
                    while let event = await group.next() {
                        continuation.yield(event)
                        _ = next()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Same scan, returned all at once.
    public static func scanAutomatic(_ results: [RuleResult]) async -> [RuleResult] {
        var results = results
        for await event in scanEvents(results) {
            if let i = results.firstIndex(where: { $0.id == event.ruleID }) { results[i].states[event.locationID] = event.state }
        }
        return results
    }
}
