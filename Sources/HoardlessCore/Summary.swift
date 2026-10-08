import Foundation

/// Totals for one category, split by what Hoardless may do with each part.
public struct CategorySummary: Sendable, Equatable {
    public var bytes: Int64 = 0
    public var safeBytes: Int64 = 0
    public var reviewBytes: Int64 = 0
    public var commandOnlyBytes: Int64 = 0
    public var protectedBytes: Int64 = 0
    /// Some location is waiting for the user to allow reading it.
    public var waitingForPermission = false
    /// Every automatic location has a final state.
    public var isComplete = true
    /// At least one location exists on disk or still needs checking.
    public var hasAnything = false

    /// Space the user can act on in some way (trash, move, or run the app's own command).
    public var actionableBytes: Int64 { safeBytes + reviewBytes + commandOnlyBytes }
}

public enum Summary {
    public static func byCategory(_ results: [RuleResult]) -> [Rule.Category: CategorySummary] {
        var out: [Rule.Category: CategorySummary] = [:]
        for result in results {
            var s = out[result.rule.category] ?? CategorySummary()
            for loc in result.locations {
                switch result.states[loc.id] ?? .notScanned {
                case .measured(let usage):
                    s.hasAnything = true
                    s.bytes += usage.bytes
                    switch (result.rule.safety, result.rule.commandOnly == true) {
                    case (.protected, _): s.protectedBytes += usage.bytes
                    case (_, true): s.commandOnlyBytes += usage.bytes
                    case (.review, false): s.reviewBytes += usage.bytes
                    case (.safe, false): s.safeBytes += usage.bytes
                    }
                case .needsPermission:
                    s.hasAnything = true
                    s.waitingForPermission = true
                case .notScanned, .scanning:
                    s.isComplete = false
                case .missing, .failed:
                    break
                }
            }
            out[result.rule.category] = s
        }
        return out
    }
}
