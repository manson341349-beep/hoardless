import Foundation
import XCTest
@testable import HoardlessCore

/// Every test acts inside its own temp folder (fake home, fake trash, fake drive). Nothing else is touched.
/// The one test that uses the real Trash only runs when HOARDLESS_REAL_TRASH_TEST=1 is set.
final class FileActionsTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var outside: URL!
    private var fakeTrash: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("hoardless-actions-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        outside = root.appendingPathComponent("outside")
        fakeTrash = root.appendingPathComponent("trash")
        for dir in [home, outside, fakeTrash] { try fm.createDirectory(at: dir!, withIntermediateDirectories: true) }
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)  // only this test's temp folder
    }

    private func write(_ url: URL, bytes: Int = 50_000) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    private func rule(_ safety: String = "review", commandOnly: Bool = false, paths: [String], env: String? = nil) throws -> Rule {
        var json: [String: Any] = [
            "id": "r", "app": "T", "category": "package-cache", "title": ["en": "t", "zh": "t"], "explain": ["en": "e", "zh": "e"],
            "paths": paths, "safety": safety, "status": "verified",
        ]
        if commandOnly {
            json["command_only"] = true
            json["official_cleanup"] = ["command": "uv cache clean", "source": "https://example.com/doc"]
        }
        if let env { json["env_overrides"] = [["var": env]] }
        return try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// Plans and measures one rule, the way the app does before offering an action.
    private func scanned(_ rule: Rule, environment: [String: String] = [:]) async -> RuleResult {
        let plan = ScanPlan.make(rules: [rule], policy: PathPolicy(home: home), environment: environment)
        return await ScanPlan.scanAutomatic(plan)[0]
    }

    private var actions: FileActions {
        let trash = fakeTrash!
        return FileActions(policy: PathPolicy(home: home)) { url in
            let landed = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        }
    }

    private func trashIsEmpty() throws -> Bool { try fm.contentsOfDirectory(atPath: fakeTrash.path).isEmpty }

    private func assertError(_ expected: ActionError, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? ActionError, expected, file: file, line: line) }
    }

    // MARK: what may be touched

    func testProtectedAndCommandOnlyAreNeverTouched() async throws {
        try write(home.appendingPathComponent(".cache/p/x.bin"))
        try write(home.appendingPathComponent(".cache/c/x.bin"))
        let p = await scanned(try rule("protected", paths: ["~/.cache/p"]))
        let c = await scanned(try rule(commandOnly: true, paths: ["~/.cache/c"]))
        for result in [p, c] {
            XCTAssertFalse(actions.canAct(result.locations[0], in: result))
            assertError(.notAllowed) { _ = try actions.trash(result.locations[0], of: result) }
            assertError(.notAllowed) { _ = try actions.move(result.locations[0], of: result, to: outside) }
        }
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".cache/p/x.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".cache/c/x.bin").path))
        XCTAssertTrue(try trashIsEmpty())
    }

    func testUnscannedLocationIsRefused() throws {
        try write(home.appendingPathComponent(".cache/a/x.bin"))
        let plan = ScanPlan.make(rules: [try rule(paths: ["~/.cache/a"])], policy: PathPolicy(home: home), environment: [:])
        assertError(.notAllowed) { _ = try actions.trash(plan[0].locations[0], of: plan[0]) }
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".cache/a/x.bin").path))
    }

    func testLinkedRulePathIsShownButNeverActedOn() async throws {
        // ~/.cache/a is a link to the user's own project: scanning follows it, actions must not.
        // The project is in an ordinary folder (not Documents), so the permission gate cannot be what stops it.
        let project = home.appendingPathComponent("Work/project")
        try write(project.appendingPathComponent("thesis.txt"))
        try fm.createDirectory(at: home.appendingPathComponent(".cache"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: home.appendingPathComponent(".cache/a"), withDestinationURL: project)
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        XCTAssertEqual(result.locations.first?.url.path, project.path)
        guard case .measured = result.states[result.locations[0].id] else { return XCTFail("must be measured, or this test proves nothing") }
        XCTAssertFalse(actions.canAct(result.locations[0], in: result))
        assertError(.notAllowed) { _ = try actions.trash(result.locations[0], of: result) }
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent("thesis.txt").path))
        XCTAssertTrue(try trashIsEmpty())
    }

    func testEnvironmentOverrideLocationIsReadOnly() async throws {
        let custom = home.appendingPathComponent("custom-cache")
        try write(custom.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"], env: "FOO_CACHE"), environment: ["FOO_CACHE": custom.path])
        let loc = try XCTUnwrap(result.locations.first { $0.url.path == custom.path })
        XCTAssertFalse(actions.canAct(loc, in: result))
        assertError(.notAllowed) { _ = try actions.trash(loc, of: result) }
        XCTAssertTrue(fm.fileExists(atPath: custom.appendingPathComponent("x.bin").path))
    }

    func testLocationNotFromThisResultIsRefusedByContainment() async throws {
        try write(home.appendingPathComponent(".cache/a/x.bin"))
        try write(home.appendingPathComponent(".cache/b/x.bin"))
        var a = await scanned(try rule(paths: ["~/.cache/a"]))
        let b = await scanned(try rule(paths: ["~/.cache/b"]))
        // Give `a` a measured state for b's location, so only the containment check can refuse it.
        a.states[b.locations[0].id] = b.states[b.locations[0].id]
        assertError(.notAllowed) { _ = try actions.trash(b.locations[0], of: a) }
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".cache/b/x.bin").path))
    }

    // MARK: changed after the scan

    func testFolderSwappedForLinkAfterScanIsRefused() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        try write(outside.appendingPathComponent("precious.txt"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        try fm.removeItem(at: dir)
        try fm.createSymbolicLink(at: dir, withDestinationURL: outside)
        assertError(.changedSinceScan) { _ = try actions.trash(result.locations[0], of: result) }
        XCTAssertTrue(fm.fileExists(atPath: outside.appendingPathComponent("precious.txt").path))
        XCTAssertTrue(try trashIsEmpty())
    }

    func testDanglingLinkSwappedInAfterScanIsRefused() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        try fm.removeItem(at: dir)
        try fm.createSymbolicLink(atPath: dir.path, withDestinationPath: "/nonexistent/hoardless")
        assertError(.changedSinceScan) { _ = try actions.trash(result.locations[0], of: result) }
        XCTAssertTrue(try trashIsEmpty())
    }

    func testFolderReplacedOrDeletedAfterScanIsRefused() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        try fm.removeItem(at: dir)
        assertError(.changedSinceScan) { _ = try actions.trash(result.locations[0], of: result) }
        try write(dir.appendingPathComponent("something-else.bin"))  // same path, a different folder
        assertError(.changedSinceScan) { _ = try actions.trash(result.locations[0], of: result) }
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("something-else.bin").path))
        XCTAssertTrue(try trashIsEmpty())
    }

    // MARK: trash and undo

    func testTrashAndUndo() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        let record = try actions.trash(result.locations[0], of: result)
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
        XCTAssertTrue(fm.fileExists(atPath: record.now.appendingPathComponent("x.bin").path))
        XCTAssertGreaterThan(record.bytes, 0)
        try actions.undo(record)
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("x.bin").path))
    }

    func testTrasherFailureIsReportedAndNothingMoves() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        let failing = FileActions(policy: PathPolicy(home: home)) { _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try failing.trash(result.locations[0], of: result)) {
            guard case .failed = $0 as? ActionError else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("x.bin").path))
    }

    func testUndoNeverOverwritesSomethingNew() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        let record = try actions.trash(result.locations[0], of: result)
        try write(dir.appendingPathComponent("new.bin"))  // the app recreated its cache meanwhile
        assertError(.undoBlocked(.occupied(dir.path))) { try actions.undo(record) }
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("new.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: record.now.path))
    }

    func testUndoOnlyPutsBackTheSameItem() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        let record = try actions.trash(result.locations[0], of: result)
        try fm.removeItem(at: record.now)
        try write(record.now.appendingPathComponent("stranger.bin"))  // a different item now sits at that name
        assertError(.undoBlocked(.notSameItem)) { try actions.undo(record) }
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
    }

    func testUndoWhenItemIsGone() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        let record = try actions.trash(result.locations[0], of: result)
        try fm.removeItem(at: record.now)  // the user emptied the Trash
        assertError(.undoBlocked(.gone(record.now.path))) { try actions.undo(record) }
    }

    func testUndoRefusesALinkedParent() async throws {
        let parent = home.appendingPathComponent(".cache/a")
        try write(parent.appendingPathComponent("b/x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a/b"]))
        let record = try actions.trash(result.locations[0], of: result)
        // The original parent is replaced by a link to a folder outside home.
        try fm.removeItem(at: parent)
        try fm.createSymbolicLink(at: parent, withDestinationURL: outside)
        assertError(.undoBlocked(.unsafeOriginal)) { try actions.undo(record) }
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: outside.path), [])
        XCTAssertTrue(fm.fileExists(atPath: record.now.path))
    }

    func testRealTrashMovesTheItemAndKeepsIt() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HOARDLESS_REAL_TRASH_TEST"] == "1",
                          "set HOARDLESS_REAL_TRASH_TEST=1 to run the test that uses your real Trash")
        let name = "hoardless-test-\(UUID().uuidString)"
        let dir = home.appendingPathComponent(".cache/\(name)")
        try write(dir.appendingPathComponent("x.bin"), bytes: 10)
        let result = await scanned(try rule(paths: ["~/.cache/\(name)"]))
        let record = try FileActions(policy: PathPolicy(home: home)).trash(result.locations[0], of: result)
        defer { try? fm.removeItem(at: record.now) }  // exactly the one item this test put in the Trash
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
        XCTAssertTrue(fm.fileExists(atPath: record.now.appendingPathComponent("x.bin").path), "in the Trash, not deleted")
        XCTAssertTrue(record.now.path.contains(".Trash"), record.now.path)
    }

    // MARK: move

    func testMoveToAnotherFolderAndBack() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("sub/x.bin"), bytes: 70_000)
        let drive = home.appendingPathComponent("Drive")
        try fm.createDirectory(at: drive.appendingPathComponent("Hoardless/r/a"), withIntermediateDirectories: true)  // name taken
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        XCTAssertEqual(actions.plannedTarget(for: result.locations[0], of: result, in: drive)?.lastPathComponent, "a 2")
        let record = try actions.move(result.locations[0], of: result, to: drive)
        XCTAssertEqual(record.now.lastPathComponent, "a 2")
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
        XCTAssertEqual((try fm.attributesOfItem(atPath: record.now.appendingPathComponent("sub/x.bin").path)[.size] as? Int), 70_000)
        try actions.undo(record)
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("sub/x.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: drive.appendingPathComponent("Hoardless/r/a").path), "what was already there stays")
    }

    func testUndoOfAMoveRemovesOnlyTheEmptyFoldersItMade() async throws {
        try write(home.appendingPathComponent(".cache/a/x.bin"))
        let drive = home.appendingPathComponent("Drive")
        try fm.createDirectory(at: drive, withIntermediateDirectories: true)
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        let record = try actions.move(result.locations[0], of: result, to: drive)
        try actions.undo(record)
        XCTAssertFalse(fm.fileExists(atPath: drive.appendingPathComponent("Hoardless").path))
        XCTAssertTrue(fm.fileExists(atPath: drive.path), "the folder the user picked stays")

        // A file of the user's next to the rule folder keeps "Hoardless"; a file inside keeps both.
        let again = await scanned(try rule(paths: ["~/.cache/a"]))
        let second = try actions.move(again.locations[0], of: again, to: drive)
        try write(drive.appendingPathComponent("Hoardless/notes.txt"), bytes: 10)
        try actions.undo(second)
        XCTAssertFalse(fm.fileExists(atPath: drive.appendingPathComponent("Hoardless/r").path))
        XCTAssertTrue(fm.fileExists(atPath: drive.appendingPathComponent("Hoardless/notes.txt").path))
        let third = await scanned(try rule(paths: ["~/.cache/a"]))
        let moved = try actions.move(third.locations[0], of: third, to: drive)
        try write(drive.appendingPathComponent("Hoardless/r/mine.txt"), bytes: 10)
        try actions.undo(moved)
        XCTAssertTrue(fm.fileExists(atPath: drive.appendingPathComponent("Hoardless/r/mine.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".cache/a/x.bin").path))
    }

    func testMoveRefusesUnsafeDestinations() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        let file = home.appendingPathComponent("Drive/file.txt")
        try write(file)
        let linkToOutside = home.appendingPathComponent("Drive/out")
        try fm.createSymbolicLink(at: linkToOutside, withDestinationURL: outside)
        for sub in ["Library/Caches/other", ".Trash", ".cache/other"] {
            try fm.createDirectory(at: home.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: dir.appendingPathComponent("inner"), withIntermediateDirectories: true)
        let cases: [(URL, ActionError.Destination)] = [
            (dir.appendingPathComponent("inner"), .insideSource),
            (outside, .notAllowedPlace),
            (URL(fileURLWithPath: "/Library"), .notAllowedPlace),
            (home, .notAllowedPlace),
            (home.appendingPathComponent(".Trash"), .notAllowedPlace),
            (home.appendingPathComponent("Library/Caches/other"), .notAllowedPlace),
            (home.appendingPathComponent(".cache/other"), .notAllowedPlace),
            (linkToOutside, .notAllowedPlace),
            (file, .notAFolder),
            (home.appendingPathComponent("does-not-exist"), .notAFolder),
        ]
        for (destination, problem) in cases {
            assertError(.badDestination(problem)) { _ = try actions.move(result.locations[0], of: result, to: destination) }
            XCTAssertNil(actions.plannedTarget(for: result.locations[0], of: result, in: destination), destination.path)
        }
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("x.bin").path))
    }

    func testMoveRefusesALinkedHoardlessFolder() async throws {
        let dir = home.appendingPathComponent(".cache/a")
        try write(dir.appendingPathComponent("x.bin"))
        let drive = home.appendingPathComponent("Drive")
        try fm.createDirectory(at: drive, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: drive.appendingPathComponent("Hoardless"), withDestinationURL: outside)
        let result = await scanned(try rule(paths: ["~/.cache/a"]))
        assertError(.badDestination(.linkInside)) { _ = try actions.move(result.locations[0], of: result, to: drive) }
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("x.bin").path))
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("r/a").path))
    }
}
