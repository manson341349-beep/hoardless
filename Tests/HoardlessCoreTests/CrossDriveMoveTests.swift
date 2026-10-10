import Foundation
import XCTest
@testable import HoardlessCore

/// Moves to another drive: copy, check, then send the original to the Trash; never a delete. These run on one drive
/// with `alwaysCopy`, except the last one, which mounts a small disk image and only runs when
/// HOARDLESS_VOLUME_TEST=1 is set. Everything happens inside this test's own temp folder.
final class CrossDriveMoveTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var fakeTrash: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("hoardless-xdrive-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        fakeTrash = root.appendingPathComponent("trash")
        for dir in [home, fakeTrash] { try fm.createDirectory(at: dir!, withIntermediateDirectories: true) }
    }

    override func tearDownWithError() throws {
        if let root, let items = fm.enumerator(atPath: root.path) {
            for case let rel as String in items { _ = chmod(root.appendingPathComponent(rel).path, 0o755) }
        }
        try? fm.removeItem(at: root)  // only this test's temp folder
    }

    // MARK: helpers

    private var source: URL { home.appendingPathComponent(".cache/a") }
    private var drive: URL { home.appendingPathComponent("Drive") }

    private func fill() throws {
        for d in ["x", "y", "z"] {
            for i in 1...3 {
                let url = source.appendingPathComponent("\(d)/f\(i).bin")
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: UInt8(i), count: 20_000 + i).write(to: url)
            }
        }
        try fm.createDirectory(at: drive, withIntermediateDirectories: true)
    }

    private func scanned() async throws -> RuleResult {
        let json: [String: Any] = ["id": "r", "app": "T", "category": "package-cache", "title": ["en": "t", "zh": "t"],
                                   "explain": ["en": "e", "zh": "e"], "paths": ["~/.cache/a"], "safety": "review", "status": "verified"]
        let rule = try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: json))
        return await ScanPlan.scanAutomatic(ScanPlan.make(rules: [rule], policy: PathPolicy(home: home), environment: [:]))[0]
    }

    private func actions(copier: (@Sendable (URL, URL) throws -> Void)? = nil,
                         refuse: String? = nil) -> FileActions {
        let trash = fakeTrash!
        let trasher: @Sendable (URL) throws -> URL = { url in
            if let refuse, url.path == refuse { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "refused"]) }
            let landed = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        }
        if let copier { return FileActions(policy: PathPolicy(home: home), trasher: trasher, copier: copier, alwaysCopy: true) }
        return FileActions(policy: PathPolicy(home: home), trasher: trasher, alwaysCopy: true)
    }

    private func files(_ url: URL) -> [String] {
        (fm.enumerator(atPath: url.path)?.allObjects as? [String] ?? []).filter { !$0.hasSuffix("/") }.sorted()
    }

    private func trashCount() -> Int { (try? fm.contentsOfDirectory(atPath: fakeTrash.path).count) ?? -1 }

    // MARK: tests

    func testMoveCopiesChecksThenTrashesTheOriginalAndUndoTakesItBack() async throws {
        try fill()
        let before = files(source)
        let originalID = FileActions.identity(source.path)
        let result = try await scanned()
        let a = actions()
        let record = try a.move(result.locations[0], of: result, to: drive)
        XCTAssertFalse(fm.fileExists(atPath: source.path))
        XCTAssertEqual(files(record.now), before, "every file arrived")
        XCTAssertNotNil(record.trashedOriginal)
        XCTAssertEqual(trashCount(), 1, "the original went to the Trash, it was not deleted")
        XCTAssertEqual(files(record.trashedOriginal!), before)
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: record.now.deletingLastPathComponent().path).allSatisfy { !$0.contains("incomplete") })

        try a.undo(record)
        XCTAssertEqual(files(source), before)
        XCTAssertEqual(FileActions.identity(source.path), originalID, "the very same folder came back out of the Trash")
        XCTAssertFalse(fm.fileExists(atPath: drive.appendingPathComponent("Hoardless").path), "the copy went to the Trash")
        XCTAssertEqual(trashCount(), 1, "only the copy is in the Trash now")
    }

    func testUndoCopiesBackWhenTheOriginalIsNoLongerInTheTrash() async throws {
        try fill()
        let before = files(source)
        let result = try await scanned()
        let a = actions()
        let record = try a.move(result.locations[0], of: result, to: drive)
        try fm.removeItem(at: record.trashedOriginal!)  // the user emptied the Trash (test folder only)
        try a.undo(record)
        XCTAssertEqual(files(source), before)
        XCTAssertFalse(fm.fileExists(atPath: record.now.path))
        XCTAssertEqual(trashCount(), 1, "the copy on the drive went to the Trash")
    }

    func testCopyThatFailsLeavesTheOriginalUntouched() async throws {
        try fill()
        let before = files(source)
        let result = try await scanned()
        let a = actions(copier: { src, dst in
            try FileManager.default.copyItem(at: src, to: dst)
            try FileManager.default.removeItem(at: dst.appendingPathComponent("y"))  // half done
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        })
        XCTAssertThrowsError(try a.move(result.locations[0], of: result, to: drive)) {
            XCTAssertEqual($0 as? ActionError, .copyIncomplete(leftover: nil, message: "disk full"))
        }
        XCTAssertEqual(files(source), before, "nothing was removed from the original")
        XCTAssertEqual(trashCount(), 1, "the partial copy went to the Trash")
        XCTAssertTrue(files(drive.appendingPathComponent("Hoardless/r")).isEmpty)
    }

    func testCopyMissingAFileIsCaughtEvenWithoutAnError() async throws {
        try fill()
        let before = files(source)
        let result = try await scanned()
        let a = actions(copier: { src, dst in
            try FileManager.default.copyItem(at: src, to: dst)
            try FileManager.default.removeItem(at: dst.appendingPathComponent("z/f2.bin"))
        })
        XCTAssertThrowsError(try a.move(result.locations[0], of: result, to: drive)) {
            XCTAssertEqual($0 as? ActionError, .copyIncomplete(leftover: nil, message: ""))
        }
        XCTAssertEqual(files(source), before)
    }

    func testSomethingWrittenDuringTheCopyStopsTheMove() async throws {
        try fill()
        let result = try await scanned()
        let late = source.appendingPathComponent("x/late.bin")
        let a = actions(copier: { src, dst in
            try FileManager.default.copyItem(at: src, to: dst)
            try Data(repeating: 9, count: 100).write(to: late)  // the app is still downloading
        })
        XCTAssertThrowsError(try a.move(result.locations[0], of: result, to: drive)) {
            XCTAssertEqual($0 as? ActionError, .changedWhileCopying(leftover: nil))
        }
        XCTAssertTrue(fm.fileExists(atPath: late.path), "the late file is still in the original")
        XCTAssertEqual(files(source).count, 13)
    }

    func testOriginalThatCannotGoToTheTrashUndoesTheMove() async throws {
        try fill()
        let before = files(source)
        let result = try await scanned()
        let a = actions(refuse: source.path)
        XCTAssertThrowsError(try a.move(result.locations[0], of: result, to: drive)) {
            XCTAssertEqual($0 as? ActionError, .originalKept(copy: nil, message: "refused"))
        }
        XCTAssertEqual(files(source), before)
        XCTAssertEqual(trashCount(), 1, "the complete copy went to the Trash")
    }

    func testUndoKeepsFilesAddedToTheCopyAfterTheMove() async throws {
        try fill()
        let before = files(source)
        let result = try await scanned()
        let a = actions()
        let record = try a.move(result.locations[0], of: result, to: drive)
        // The app was pointed at the new place and downloaded something there.
        try Data(repeating: 7, count: 5_000).write(to: record.now.appendingPathComponent("x/new-model.bin"))
        try a.undo(record)
        XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent("x/new-model.bin").path),
                      "the file added on the drive came back too")
        XCTAssertEqual(files(source), (before + ["x/new-model.bin"]).sorted())
        XCTAssertTrue(fm.fileExists(atPath: record.trashedOriginal!.path), "the old original stays in the Trash")
    }

    func testFinderDSStoreInTheCopyIsNotAMismatch() {
        let source = ["": "d", "a": "f:10:1"]
        XCTAssertTrue(FileActions.sameContentShape(source, ["": "d", "a": "f:10:5", ".DS_Store": "f:6148:5"]))
        XCTAssertTrue(FileActions.sameContentShape(source, ["": "d", "a": "f:10:5", "sub/.DS_Store": "f:6148:5"]))
    }

    func testDotUnderscoreFilesFromExFATAreNotAMismatch() {
        let source = ["": "d", "a": "f:10:1"]
        XCTAssertTrue(FileActions.sameContentShape(source, ["": "d", "a": "f:10:5", "._a": "f:4096:5"]))
        XCTAssertFalse(FileActions.sameContentShape(source, ["": "d", "a": "f:10:5", "b": "f:1:1"]))
        XCTAssertFalse(FileActions.sameContentShape(source, ["": "d", "a": "f:9:1"]))
        XCTAssertFalse(FileActions.sameContentShape(source, ["": "d"]))
    }

    /// The case the audit reproduced: a subfolder whose files can't be removed. Foundation's own cross-volume move
    /// deleted part of the original before failing; this must now succeed and keep the whole original in the Trash.
    func testRealSecondVolumeWithAnUndeletableSubfolder() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HOARDLESS_VOLUME_TEST"] == "1", "set HOARDLESS_VOLUME_TEST=1")
        try fill()
        let locked = source.appendingPathComponent("y")
        XCTAssertEqual(chmod(locked.path, 0o555), 0)
        let name = "HLTEST-" + UUID().uuidString.prefix(8)
        let image = root.appendingPathComponent("drive.dmg"), mount = URL(fileURLWithPath: "/Volumes/\(name)")
        func run(_ args: [String]) throws -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            try p.run(); p.waitUntilExit(); return p.terminationStatus
        }
        XCTAssertEqual(try run(["create", "-size", "20m", "-fs", "HFS+", "-volname", name, "-quiet", image.path]), 0)
        XCTAssertFalse(fm.fileExists(atPath: mount.path))
        XCTAssertEqual(try run(["attach", image.path, "-nobrowse", "-quiet"]), 0)
        defer { _ = try? run(["detach", mount.path, "-quiet"]) }
        let before = files(source)
        let result = try await scanned()
        let trash = fakeTrash!
        let real = FileActions(policy: PathPolicy(home: home)) { url in
            let landed = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        }
        let folder = URL(fileURLWithPath: mount.path).resolvingSymlinksInPath()
        let record = try real.move(result.locations[0], of: result, to: folder)
        XCTAssertNotNil(record.trashedOriginal, "a different volume took the copy path")
        XCTAssertEqual(files(record.now), before)
        XCTAssertEqual(files(record.trashedOriginal!), before, "the whole original is in the Trash")
        try real.undo(record)
        XCTAssertEqual(files(source), before)
    }
}
