import Foundation
import XCTest
@testable import HoardlessCore

/// Ticking several rules, acting once, undoing the batch. Every test works inside its own temp folder
/// (fake home, fake Trash). Nothing else is touched.
final class BatchActionsTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var fakeTrash: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("hoardless-batch-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        fakeTrash = root.appendingPathComponent("trash")
        for dir in [home, fakeTrash] { try fm.createDirectory(at: dir!, withIntermediateDirectories: true) }
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)  // only this test's temp folder
    }

    // MARK: helpers

    private func write(_ rel: String, bytes: Int = 40_000) throws {
        let url = home.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    private func exists(_ rel: String) -> Bool { fm.fileExists(atPath: home.appendingPathComponent(rel).path) }

    private func rule(_ id: String, _ safety: String = "review", paths: [String]) throws -> Rule {
        let json: [String: Any] = [
            "id": id, "app": "T", "category": "package-cache", "title": ["en": id, "zh": id], "explain": ["en": "e", "zh": "e"],
            "paths": paths, "safety": safety, "status": "verified",
        ]
        return try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func scanned(_ rules: [Rule]) async -> [RuleResult] {
        await ScanPlan.scanAutomatic(ScanPlan.make(rules: rules, policy: PathPolicy(home: home), environment: [:]))
    }

    private var actions: FileActions {
        let trash = fakeTrash!
        return FileActions(policy: PathPolicy(home: home)) { url in
            let landed = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        }
    }

    private func everything(_ results: [RuleResult]) -> Set<String> { Set(results.flatMap { $0.locations.map(\.id) }) }

    // MARK: picking

    func testOnlyActionableTickedLocationsBecomeItems() async throws {
        try write(".cache/a/x.bin")
        try write(".cache/p/x.bin")
        let results = await scanned([try rule("a", paths: ["~/.cache/a"]), try rule("p", "protected", paths: ["~/.cache/p"])])
        XCTAssertTrue(actions.items(for: [], in: results).isEmpty, "nothing is ticked for the user")
        let items = actions.items(for: everything(results), in: results)
        XCTAssertEqual(items.map(\.ruleID), ["a"], "a protected location never becomes an item, even if its id is ticked")
    }

    // MARK: acting

    func testEachItemIsTriedAndAFailureDoesNotStopTheRest() async throws {
        try write(".cache/a/x.bin")
        try write(".cache/b/x.bin")
        let results = await scanned([try rule("a", paths: ["~/.cache/a"]), try rule("b", paths: ["~/.cache/b"])])
        let items = actions.items(for: everything(results), in: results)
        // b is replaced after the scan, so it must fail; it is first, so a stopped loop would skip a.
        try fm.removeItem(at: home.appendingPathComponent(".cache/b"))
        try write(".cache/b/other.bin")
        let ordered = items.sorted { a, _ in a.ruleID == "b" }
        let outcome = actions.run(.trash, ordered, in: results)
        XCTAssertEqual(outcome.records.map(\.ruleID), ["a"])
        XCTAssertEqual(outcome.failures.map(\.error), [.changedSinceScan])
        XCTAssertFalse(exists(".cache/a/x.bin"))
        XCTAssertTrue(exists(".cache/b/other.bin"))
    }

    func testItemWhoseRuleIsGoneIsNotActedOn() async throws {
        try write(".cache/a/x.bin")
        let results = await scanned([try rule("a", paths: ["~/.cache/a"])])
        let items = actions.items(for: everything(results), in: results)
        let outcome = actions.run(.trash, items, in: [])  // a rescan no longer has the rule
        XCTAssertTrue(outcome.records.isEmpty)
        XCTAssertEqual(outcome.failures.map(\.error), [.changedSinceScan])
        XCTAssertTrue(exists(".cache/a/x.bin"))
    }

    func testItemNotMeasuredInTheLatestScanIsRefused() async throws {
        try write(".cache/a/x.bin")
        let results = await scanned([try rule("a", paths: ["~/.cache/a"])])
        let items = actions.items(for: everything(results), in: results)
        let unmeasured = ScanPlan.make(rules: [try rule("a", paths: ["~/.cache/a"])], policy: PathPolicy(home: home), environment: [:])
        let outcome = actions.run(.trash, items, in: unmeasured)
        XCTAssertEqual(outcome.failures.map(\.error), [.notAllowed])
        XCTAssertTrue(exists(".cache/a/x.bin"))
    }

    // MARK: Undo

    func testAFailedBatchKeepsThePreviousUndo() async throws {
        try write(".cache/a/x.bin")
        let results = await scanned([try rule("a", paths: ["~/.cache/a"])])
        let first = actions.run(.trash, actions.items(for: everything(results), in: results), in: results)
        var undo = UndoHistory.after(first, previous: [])
        XCTAssertEqual(undo.map(\.ruleID), ["a"])
        let failed = actions.run(.trash, actions.items(for: everything(results), in: results), in: [])
        XCTAssertTrue(failed.records.isEmpty)
        undo = UndoHistory.after(failed, previous: undo)
        XCTAssertEqual(undo.map(\.ruleID), ["a"], "a batch that changed nothing must not take the Undo away")
    }

    func testUndoPutsBackLastFirstAndKeepsWhatFailedForARetry() async throws {
        try write(".cache/a/x.bin")
        try write(".cache/b/x.bin")
        let results = await scanned([try rule("a", paths: ["~/.cache/a"]), try rule("b", paths: ["~/.cache/b"])])
        let items = actions.items(for: everything(results), in: results).sorted { $0.ruleID < $1.ruleID }
        let batch = actions.run(.trash, items, in: results)
        XCTAssertEqual(batch.records.map(\.ruleID), ["a", "b"])
        try write(".cache/a/new.bin")  // something new now sits where a was
        let undo = actions.undoAll(batch.records)
        XCTAssertEqual(undo.restored.map(\.ruleID), ["b"])
        XCTAssertEqual(undo.failed.map(\.error), [.undoBlocked(.occupied(home.appendingPathComponent(".cache/a").path))])
        XCTAssertTrue(exists(".cache/b/x.bin"))
        XCTAssertTrue(exists(".cache/a/new.bin"), "Undo never overwrites")
        let remaining = UndoHistory.after(undo)
        XCTAssertEqual(remaining.map(\.ruleID), ["a"], "what failed stays undoable")
        try fm.removeItem(at: home.appendingPathComponent(".cache/a"))
        let retry = actions.undoAll(remaining)
        XCTAssertEqual(retry.restored.map(\.ruleID), ["a"])
        XCTAssertTrue(exists(".cache/a/x.bin"))
        XCTAssertTrue(UndoHistory.after(retry).isEmpty)
    }

    func testUndoGoesLastFirstAndKeepsTheOriginalOrderOfWhatIsLeft() async throws {
        for name in ["a", "b", "c"] { try write(".cache/\(name)/x.bin") }
        let rules = try ["a", "b", "c"].map { try rule($0, paths: ["~/.cache/\($0)"]) }
        let results = await scanned(rules)
        let items = actions.items(for: everything(results), in: results).sorted { $0.ruleID < $1.ruleID }
        let batch = actions.run(.trash, items, in: results)
        XCTAssertEqual(batch.records.map(\.ruleID), ["a", "b", "c"])
        for name in ["a", "c"] { try write(".cache/\(name)/new.bin") }
        let undo = actions.undoAll(batch.records)
        XCTAssertEqual(undo.restored.map(\.ruleID), ["b"])
        XCTAssertEqual(undo.failed.map(\.record.ruleID), ["c", "a"], "the last one is tried first")
        XCTAssertEqual(UndoHistory.after(undo).map(\.ruleID), ["a", "c"], "what is left keeps the batch's order")
        for name in ["a", "c"] { try fm.removeItem(at: home.appendingPathComponent(".cache/\(name)")) }
        let retry = actions.undoAll(UndoHistory.after(undo))
        XCTAssertEqual(retry.restored.map(\.ruleID), ["c", "a"])
    }

    // MARK: moving

    func testMoveDestinationIsCheckedBeforeAsking() async throws {
        try write(".cache/a/x.bin")
        try write(".cache/b/x.bin")
        let results = await scanned([try rule("a", paths: ["~/.cache/a"]), try rule("b", paths: ["~/.cache/b"])])
        let items = actions.items(for: everything(results), in: results)
        let archive = home.appendingPathComponent("Archive")
        let library = home.appendingPathComponent("Library")
        for dir in [archive, library] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        let targets = try XCTUnwrap(actions.plannedTargets(items, in: results, folder: archive))
        XCTAssertEqual(Set(targets.values.map { $0.deletingLastPathComponent().lastPathComponent }), ["a", "b"])
        XCTAssertNil(actions.plannedTargets(items, in: results, folder: library), "Library is refused before the sheet")
        XCTAssertNil(actions.plannedTargets(items, in: results, folder: home.appendingPathComponent(".cache/a")), "never inside a source")
    }

    func testMovedBatchCanBeUndone() async throws {
        try write(".cache/a/x.bin")
        try write(".cache/b/x.bin")
        let results = await scanned([try rule("a", paths: ["~/.cache/a"]), try rule("b", paths: ["~/.cache/b"])])
        let items = actions.items(for: everything(results), in: results)
        let archive = home.appendingPathComponent("Archive")
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        let batch = actions.run(.move(to: archive), items, in: results)
        XCTAssertEqual(batch.records.count, 2)
        XCTAssertTrue(batch.records.allSatisfy { $0.kind == .moved })
        XCTAssertFalse(exists(".cache/a/x.bin") || exists(".cache/b/x.bin"))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: fakeTrash.path).isEmpty, "a move never uses the Trash")
        let undo = actions.undoAll(batch.records)
        XCTAssertEqual(undo.restored.count, 2)
        XCTAssertTrue(exists(".cache/a/x.bin") && exists(".cache/b/x.bin"))
    }
}
