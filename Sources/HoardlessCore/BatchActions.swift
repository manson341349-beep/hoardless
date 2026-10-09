import Foundation

/// One ticked location, named by its rule so it can be found again in the latest scan.
public struct BatchItem: Sendable, Hashable {
    public let ruleID: String
    public let location: Location

    public init(ruleID: String, location: Location) {
        self.ruleID = ruleID
        self.location = location
    }
}

public enum BatchKind: Sendable, Equatable {
    case trash
    case move(to: URL)
}

public struct BatchOutcome: Sendable {
    public var records: [ActionRecord] = []
    public var failures: [(location: Location, error: ActionError)] = []
    public init() {}
}

public struct UndoOutcome: Sendable {
    public var restored: [ActionRecord] = []
    public var failed: [(record: ActionRecord, error: ActionError)] = []
    public init() {}
}

/// Ticking several rules, acting on them in one go, and undoing that. Every single item still goes through
/// `trash`, `move` and `undo`, which re-check it on disk right before changing anything.
extension FileActions {
    /// The locations of a rule that may be trashed or moved.
    public func actionable(_ result: RuleResult) -> [Location] {
        result.locations.filter { canAct($0, in: result) }
    }

    /// The ticked location ids that may be acted on in these results. Anything else ticked is dropped.
    public func items(for selection: Set<String>, in results: [RuleResult]) -> [BatchItem] {
        results.flatMap { r in actionable(r).filter { selection.contains($0.id) }.map { BatchItem(ruleID: r.id, location: $0) } }
    }

    /// Where each item would land in `folder`, by location id; nil if any of them can't go there, so the move is
    /// refused before the user is asked to confirm it.
    public func plannedTargets(_ items: [BatchItem], in results: [RuleResult], folder: URL) -> [String: URL]? {
        var targets: [String: URL] = [:]
        for item in items {
            guard let result = results.first(where: { $0.id == item.ruleID }),
                  let target = plannedTarget(for: item.location, of: result, in: folder) else { return nil }
            targets[item.location.id] = target
        }
        return targets
    }

    /// Acts on each item against the latest scan. An item that fails (its rule is gone, it may no longer be acted
    /// on, it changed on disk…) is reported and the others still go ahead.
    public func run(_ kind: BatchKind, _ items: [BatchItem], in results: [RuleResult]) -> BatchOutcome {
        var outcome = BatchOutcome()
        for item in items {
            guard let result = results.first(where: { $0.id == item.ruleID }) else {
                outcome.failures.append((item.location, .changedSinceScan)); continue
            }
            do {
                switch kind {
                case .trash: outcome.records.append(try trash(item.location, of: result))
                case .move(let folder): outcome.records.append(try move(item.location, of: result, to: folder))
                }
            } catch let error as ActionError {
                outcome.failures.append((item.location, error))
            } catch {
                outcome.failures.append((item.location, .failed(error.localizedDescription)))
            }
        }
        return outcome
    }

    /// Puts a batch back, last item first. What can't be put back is reported, never forced.
    public func undoAll(_ records: [ActionRecord]) -> UndoOutcome {
        var outcome = UndoOutcome()
        for record in records.reversed() {
            do {
                try undo(record)
                outcome.restored.append(record)
            } catch let error as ActionError {
                outcome.failed.append((record, error))
            } catch {
                outcome.failed.append((record, .failed(error.localizedDescription)))
            }
        }
        return outcome
    }
}

/// What the Undo button offers.
public enum UndoHistory {
    /// After a batch: its records, or the previous ones when it changed nothing (a failed batch must not take away
    /// the Undo of the last one that worked).
    public static func after(_ batch: BatchOutcome, previous: [ActionRecord]) -> [ActionRecord] {
        batch.records.isEmpty ? previous : batch.records
    }

    /// After an undo: whatever could not be put back stays undoable, in its original order, so it can be retried.
    public static func after(_ undo: UndoOutcome) -> [ActionRecord] {
        undo.failed.map(\.record).reversed()
    }
}
