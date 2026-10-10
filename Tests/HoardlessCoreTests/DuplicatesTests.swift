import Darwin
import Foundation
import XCTest
@testable import HoardlessCore

/// Every test works inside its own temp folder (fake home, fake Trash). Nothing else is touched.
final class DuplicatesTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var fakeTrash: URL!
    private var policy: PathPolicy!
    private let fm = FileManager.default
    private let size = 300_000

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("hoardless-dups-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        fakeTrash = root.appendingPathComponent("trash")
        for dir in [home, fakeTrash] { try fm.createDirectory(at: dir!, withIntermediateDirectories: true) }
        policy = PathPolicy(home: home)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)  // only this test's temp folder
    }

    // MARK: helpers

    private func content(_ seed: UInt8) -> Data {
        Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    @discardableResult
    private func write(_ rel: String, _ data: Data) throws -> URL {
        let url = home.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func search(_ rels: [String], appFolders: [URL] = []) -> DuplicateSearch {
        DuplicateSearch(roots: rels.map { home.appendingPathComponent($0) }, minimumSize: 1000, appFolders: appFolders, policy: policy)
    }

    private func groups(_ s: DuplicateSearch) throws -> [DuplicateGroup] {
        try XCTUnwrap(DuplicateFinder.find(s)).0
    }

    private func names(_ g: DuplicateGroup) -> [String] { g.files.map(\.url.lastPathComponent).sorted() }

    private var actions: FileActions {
        let trash = fakeTrash!
        return FileActions(policy: policy) { url in
            let target = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }

    // MARK: finding

    func testFindsOnlyIdenticalContent() throws {
        try write("Downloads/a.bin", content(1))
        try write("Downloads/sub/b.bin", content(1))
        var middle = content(1)
        middle[size / 2] ^= 0xff  // same size, same start and end: only the full hash tells it apart
        try write("Downloads/c.bin", middle)
        try write("Downloads/small1.txt", Data("same".utf8))
        try write("Downloads/small2.txt", Data("same".utf8))
        let found = try groups(search(["Downloads"]))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(names(found[0]), ["a.bin", "b.bin"])
        XCTAssertTrue(found[0].files.allSatisfy { $0.viewOnly == nil })
        XCTAssertEqual(found[0].wasted, found[0].files.map(\.freeable).min())
    }

    func testHardLinkIsOneFileAndViewOnly() throws {
        let a = try write("Downloads/a.bin", content(2))
        try fm.linkItem(at: a, to: home.appendingPathComponent("Downloads/a-link.bin"))
        XCTAssertTrue(try groups(search(["Downloads"])).isEmpty, "two names of one file are not duplicates")

        try write("Downloads/b.bin", content(2))
        let found = try groups(search(["Downloads"]))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].files.count, 2)
        let linked = try XCTUnwrap(found[0].files.first { $0.url.lastPathComponent != "b.bin" })
        XCTAssertEqual(linked.viewOnly, .hardLinked)
        XCTAssertEqual(linked.freeable, 0)
    }

    func testSymlinksAreNeverFollowed() throws {
        let a = try write("Downloads/a.bin", content(3))
        try write("Elsewhere/b.bin", content(3))
        try fm.createSymbolicLink(at: home.appendingPathComponent("Downloads/link.bin"), withDestinationURL: a)
        try fm.createSymbolicLink(at: home.appendingPathComponent("Downloads/dirlink"),
                                  withDestinationURL: home.appendingPathComponent("Elsewhere"))
        XCTAssertTrue(try groups(search(["Downloads"])).isEmpty)
    }

    func testClonesFreeNothing() throws {
        let a = try write("Downloads/a.bin", content(4))
        let b = home.appendingPathComponent("Downloads/b.bin")
        guard clonefile(a.path, b.path, 0) == 0 else { throw XCTSkip("temp folder is not on APFS") }
        let found = try groups(search(["Downloads"]))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].wasted, 0, "a clone shares its space; trashing it frees nothing")
    }

    func testSkippedAndViewOnlyPlaces() throws {
        let data = content(5)
        try write("Downloads/keep.bin", data)
        // Never looked inside:
        try write("Downloads/.hidden/x.bin", data)
        try write("Downloads/Thing.app/Contents/x.bin", data)
        try write("Downloads/web/node_modules/x.bin", data)
        try write("Downloads/env/pyvenv.cfg", Data("home = /usr".utf8))
        try write("Downloads/env/lib/x.bin", data)
        XCTAssertTrue(try groups(search(["Downloads"])).isEmpty)

        // Listed but view-only:
        try write("Downloads/project/.git/HEAD", Data("ref".utf8))
        try write("Downloads/project/assets/x.bin", data)
        try write("Movies/Editor/User Data/Projects/x.bin", data)
        try write("Movies/CapCut/Presets/x.bin", data)
        let capcut = Location(display: "~/Movies/CapCut/User Data/Cache/effect",
                              url: home.appendingPathComponent("Movies/CapCut/User Data/Cache/effect"), origin: .rulePath, needsPermission: false)
        let zones = DuplicateSearch.appFolders(for: [capcut], policy: policy)
        XCTAssertEqual(zones.map(\.path), [home.appendingPathComponent("Movies/CapCut").path])
        let found = try groups(search(["Downloads", "Movies"], appFolders: zones))
        XCTAssertEqual(found.count, 1)
        let byName = Dictionary(uniqueKeysWithValues: found[0].files.map { ($0.url.path.replacingOccurrences(of: home.path + "/", with: ""), $0.viewOnly) })
        XCTAssertEqual(byName["Downloads/keep.bin"], .some(nil))
        XCTAssertEqual(byName["Downloads/project/assets/x.bin"], .codeRepository)
        XCTAssertEqual(byName["Movies/Editor/User Data/Projects/x.bin"], .appFolder("~/Movies/Editor/User Data"))
        XCTAssertEqual(byName["Movies/CapCut/Presets/x.bin"], .appFolder("~/Movies/CapCut"))
        XCTAssertEqual(found[0].wasted, found[0].files.first { $0.viewOnly == nil }!.freeable,
                       "with view-only copies staying, the one pickable copy can go")
    }

    func testSettingsFolderIsNotWidened() {
        let drafts = Location(display: "~/Documents/MyDrafts", url: home.appendingPathComponent("Documents/MyDrafts/sub"),
                              origin: .appSetting("~/x"), needsPermission: true)
        XCTAssertEqual(DuplicateSearch.appFolders(for: [drafts], policy: policy).map(\.lastPathComponent), ["sub"])
    }

    func testRootChecks() throws {
        try fm.createDirectory(at: home.appendingPathComponent("Library/Models"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        try write("Downloads/file.bin", content(6))
        func check(_ url: URL) -> DuplicateSearch.RootProblem? {
            if case .failure(let p) = DuplicateSearch.checkRoot(url, policy: policy) { return p }
            return nil
        }
        XCTAssertEqual(check(home), .wholeHome)
        XCTAssertEqual(check(home.appendingPathComponent("Library/Models")), .library)
        XCTAssertEqual(check(home.appendingPathComponent(".Trash")), .trash)
        XCTAssertEqual(check(root), .outsideHome)
        XCTAssertEqual(check(home.appendingPathComponent("Downloads/file.bin")), .notAFolder)
        XCTAssertNil(check(home.appendingPathComponent("Downloads")))
        let s = search(["Downloads", "Downloads/sub", "Library/Models"])
        XCTAssertEqual(s.roots.map(\.lastPathComponent), ["Downloads"], "nested and refused folders are dropped")
    }

    func testCancelReturnsNothing() throws {
        try write("Downloads/a.bin", content(7))
        try write("Downloads/b.bin", content(7))
        XCTAssertNil(DuplicateFinder.find(search(["Downloads"]), isCancelled: { true }))
    }

    // MARK: picking

    func testAtLeastOneCopyStaysPickable() throws {
        for n in ["a", "b", "c"] { try write("Downloads/\(n).bin", content(8)) }
        let g = try XCTUnwrap(groups(search(["Downloads"])).first)
        let (a, b, c) = (g.files[0], g.files[1], g.files[2])
        XCTAssertTrue(g.canSelect(a, alreadySelected: []))
        XCTAssertTrue(g.canSelect(b, alreadySelected: [a.id]))
        XCTAssertFalse(g.canSelect(c, alreadySelected: [a.id, b.id]), "the last copy can never be picked")
        XCTAssertTrue(g.canSelect(a, alreadySelected: [a.id, b.id]), "unpicking is always allowed")
    }

    // MARK: trashing

    func testTrashesPickedCopyAndUndoes() throws {
        let a = try write("Downloads/a.bin", content(9))
        let b = try write("Downloads/b.bin", content(9))
        let s = search(["Downloads"])
        let found = try groups(s)
        let out = actions.trashDuplicates([a.path], in: found, search: s)
        XCTAssertEqual(out.records.count, 1)
        XCTAssertTrue(out.failures.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: a.path))
        XCTAssertTrue(fm.fileExists(atPath: b.path))
        try actions.undo(out.records[0])
        XCTAssertEqual(try Data(contentsOf: a), content(9))
    }

    func testNeverTrashesEveryCopy() throws {
        let a = try write("Downloads/a.bin", content(10))
        let b = try write("Downloads/b.bin", content(10))
        let s = search(["Downloads"])
        let out = actions.trashDuplicates([a.path, b.path], in: try groups(s), search: s)
        XCTAssertTrue(out.records.isEmpty)
        XCTAssertEqual(out.failures.map { $0.error }, [.noCopyLeft, .noCopyLeft])
        XCTAssertTrue(fm.fileExists(atPath: a.path) && fm.fileExists(atPath: b.path))
    }

    func testKeeperChangedAfterScan() throws {
        let a = try write("Downloads/a.bin", content(11))
        let b = try write("Downloads/b.bin", content(11))
        let s = search(["Downloads"])
        let found = try groups(s)
        try content(12).write(to: b)  // the copy that was going to stay is now different
        let out = actions.trashDuplicates([a.path], in: found, search: s)
        XCTAssertEqual(out.failures.map { $0.error }, [.noCopyLeft])
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }

    func testKeeperDeletedAfterScan() throws {
        let a = try write("Downloads/a.bin", content(13))
        let b = try write("Downloads/b.bin", content(13))
        let s = search(["Downloads"])
        let found = try groups(s)
        try fm.removeItem(at: b)
        let out = actions.trashDuplicates([a.path], in: found, search: s)
        XCTAssertEqual(out.failures.map { $0.error }, [.noCopyLeft])
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }

    func testPickedCopyChangedAfterScan() throws {
        let a = try write("Downloads/a.bin", content(14))
        try write("Downloads/b.bin", content(14))
        let s = search(["Downloads"])
        let found = try groups(s)
        try fm.removeItem(at: a)
        try content(15).write(to: a)  // a different file now has the picked name
        let out = actions.trashDuplicates([a.path], in: found, search: s)
        XCTAssertEqual(out.failures.map { $0.error }, [.changedSinceScan])
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }

    func testBecameViewOnlyAfterScan() throws {
        let a = try write("Downloads/work/a.bin", content(16))
        try write("Downloads/b.bin", content(16))
        let s = search(["Downloads"])
        let found = try groups(s)
        try write("Downloads/work/.git/HEAD", Data("ref".utf8))  // the folder became a repository
        let out = actions.trashDuplicates([a.path], in: found, search: s)
        XCTAssertEqual(out.failures.map { $0.error }, [.notAllowed])
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }

    func testRefusesOutsideTheSearchedFolders() throws {
        let a = try write("Downloads/a.bin", content(17))
        try write("Downloads/b.bin", content(17))
        try fm.createDirectory(at: home.appendingPathComponent("Movies"), withIntermediateDirectories: true)
        let found = try groups(search(["Downloads"]))
        let other = search(["Movies"])
        let out = actions.trashDuplicates([a.path], in: found, search: other)
        XCTAssertEqual(out.failures.map { $0.error }, [.notAllowed])
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }

    func testRefusesWhenAFolderInThePathBecameALink() throws {
        let a = try write("Downloads/work/a.bin", content(18))
        try write("Downloads/b.bin", content(18))
        let s = search(["Downloads"])
        let found = try groups(s)
        let work = home.appendingPathComponent("Downloads/work")
        let moved = home.appendingPathComponent("Downloads/work2")
        try fm.moveItem(at: work, to: moved)
        try fm.createSymbolicLink(at: work, withDestinationURL: moved)  // same file, now reached through a link
        let out = actions.trashDuplicates([a.path], in: found, search: s)
        XCTAssertEqual(out.failures.map { $0.error }, [.notAllowed])
        XCTAssertTrue(fm.fileExists(atPath: moved.appendingPathComponent("a.bin").path))
    }

    func testViewOnlyCopyIsNeverTrashed() throws {
        let inRepo = try write("Downloads/project/a.bin", content(19))
        try write("Downloads/project/.git/HEAD", Data("ref".utf8))
        try write("Downloads/b.bin", content(19))
        let s = search(["Downloads"])
        let out = actions.trashDuplicates([inRepo.path], in: try groups(s), search: s)
        XCTAssertEqual(out.failures.map { $0.error }, [.notAllowed])
        XCTAssertTrue(fm.fileExists(atPath: inRepo.path))
    }

    // MARK: found in the 2026-10-09 safety review

    func testCopyInAnAppFolderDoesNotCountAsTheOneThatStays() throws {
        // A cache copy can vanish (the app cleans it, or Hoardless's own rules trash it), so it never protects the last real copy.
        let clip = try write("Downloads/clip.png", content(20))
        try write("Movies/CapCut/User Data/Cache/image/abc", content(20))
        let s = search(["Downloads", "Movies"])
        let g = try XCTUnwrap(groups(s).first)
        let downloads = try XCTUnwrap(g.files.first { $0.url == clip })
        XCTAssertFalse(g.canSelect(downloads, alreadySelected: []), "the only copy outside app data must stay")
        XCTAssertNil(g.suggestedKeeper.flatMap { $0.viewOnly }, "an app-data copy is never the suggested keeper")
        XCTAssertEqual(g.wasted, 0)
        let out = actions.trashDuplicates([clip.path], in: [g], search: s)
        XCTAssertEqual(out.failures.map { $0.error }, [.noCopyLeft])
        XCTAssertTrue(fm.fileExists(atPath: clip.path))
    }

    func testKeepOneNeverPicksTheKeeper() throws {
        for n in ["a", "b", "c"] { try write("Downloads/\(n).bin", content(21)) }
        let g = try XCTUnwrap(groups(search(["Downloads"])).first)
        let keeper = try XCTUnwrap(g.suggestedKeeper)
        let picked = g.keepingOne(current: Set(g.files.map(\.id)))  // even if the user had ticked everything
        XCTAssertFalse(picked.contains(keeper.id))
        XCTAssertEqual(picked.count, 2)
    }

    func testSearchFolderInsideAPackageIsRefusedAndItsFilesStayViewOnly() throws {
        try write("Downloads/Thing.app/Contents/Resources/model.bin", content(22))
        try write("Downloads/Thing.app/Contents/Resources/copy.bin", content(22))
        let inside = home.appendingPathComponent("Downloads/Thing.app/Contents")
        if case .success = DuplicateSearch.checkRoot(inside, policy: policy) { XCTFail("a folder inside a package must be refused") }
        if case .success = DuplicateSearch.checkRoot(home.appendingPathComponent("Downloads/Thing.app"), policy: policy) {
            XCTFail("a package must be refused")
        }
        let s = search(["Downloads"])
        XCTAssertNotNil(s.viewOnlyReason(inside.appendingPathComponent("Resources/model.bin")))
    }

    func testAppleMediaLibrariesAreViewOnly() throws {
        try write("Downloads/film.mp4", content(23))
        try write("Movies/TV/Media/Movies/film.mp4", content(23))
        try write("Music/Music/Media.localized/Music/film.mp4", content(23))
        let found = try groups(search(["Downloads", "Movies", "Music"]))
        let g = try XCTUnwrap(found.first)
        XCTAssertEqual(g.files.filter { $0.viewOnly == nil }.map { $0.url.lastPathComponent }, ["film.mp4"])
        XCTAssertEqual(g.files.filter { $0.viewOnly == nil }.first?.url.deletingLastPathComponent().lastPathComponent, "Downloads")
    }

    func testKeeperRewrittenWithItsOldTimeIsNotUnchanged() throws {
        let a = try write("Downloads/a.bin", content(24))
        let b = try write("Downloads/b.bin", content(24))
        let s = search(["Downloads"])
        let found = try groups(s)
        var before = stat()
        XCTAssertEqual(lstat(b.path, &before), 0)
        Thread.sleep(forTimeInterval: 1.1)
        let handle = try FileHandle(forWritingTo: b)  // same file, same size, different bytes
        try handle.write(contentsOf: content(25))
        try handle.close()
        var times = [before.st_atimespec, before.st_mtimespec]  // put the old time back exactly, like cp -p / rsync -t
        XCTAssertEqual(utimensat(AT_FDCWD, b.path, &times, 0), 0)
        var after = stat()
        XCTAssertEqual(lstat(b.path, &after), 0)
        XCTAssertEqual(after.st_mtimespec.tv_nsec, before.st_mtimespec.tv_nsec, "the test must really restore the time")
        let out = actions.trashDuplicates([a.path], in: found, search: s)
        XCTAssertEqual(out.failures.map { $0.error }, [.noCopyLeft])
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }

    func testRefusedSearchFoldersAreReported() throws {
        try fm.createDirectory(at: home.appendingPathComponent("Library/Models"), withIntermediateDirectories: true)
        let s = search(["Library/Models", "Missing"])
        XCTAssertTrue(s.roots.isEmpty)
        XCTAssertEqual(s.refused.map(\.problem), [.library, .notAFolder])
    }

    func testWrongItemTrashedInARaceIsPutBack() throws {
        let a = try write("Downloads/a.bin", content(26))
        try write("Downloads/b.bin", content(26))
        let s = search(["Downloads"])
        let found = try groups(s)
        let intruder = try write("Downloads/other.bin", content(27))
        let trash = fakeTrash!
        // Something swaps the file at the last moment, after every check passed.
        let racy = FileActions(policy: policy) { url in
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: intruder, to: url)
            let target = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        let out = racy.trashDuplicates([a.path], in: found, search: s)
        XCTAssertTrue(out.records.isEmpty)
        XCTAssertEqual(out.failures.map { $0.error }, [.changedSinceScan])
        XCTAssertEqual(try Data(contentsOf: a), content(27), "the item that was moved by mistake is back where it was")
    }
    // MARK: app folders from the rules (audit 2026-10-10)

    private func rule(_ id: String, _ extra: [String: Any]) throws -> Rule {
        var json: [String: Any] = ["id": id, "app": "T", "category": "ai-models", "title": ["en": id, "zh": id],
                                   "explain": ["en": "e", "zh": "e"], "safety": "protected", "status": "verified"]
        json.merge(extra) { $1 }
        return try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testFolderASettingNamesIsProtectedNotOnlyItsSubpath() throws {
        // ComfyUI-style: settings name the base folder, the rule adds "models"; the input folder is app data too.
        try write(".foo/base.txt", Data(home.appendingPathComponent("Studio/ComfyUI").path.utf8))
        let r = try rule("comfy", ["paths": ["~/.foo/default/models"],
                                   "app_settings": [["file": "~/.foo/base.txt", "format": "pointer", "subpath": "models"]]])
        let zones = DuplicateSearch.appFolders(for: [r], policy: policy, environment: [:])
        XCTAssertTrue(zones.contains(home.appendingPathComponent("Studio/ComfyUI")))
        let data = content(21)
        try write("Downloads/portrait.png", data)
        try write("Studio/ComfyUI/input/portrait.png", data)
        let found = try groups(search(["Downloads", "Studio"], appFolders: zones))
        let input = try XCTUnwrap(found.first?.files.first { $0.url.path.contains("ComfyUI/input") })
        XCTAssertEqual(input.viewOnly, .appFolder("~/Studio/ComfyUI"))
    }

    func testAFolderTheScannerRefusesIsStillProtected() throws {
        // Drafts set to the whole Movies folder: the scanner refuses it, the duplicate finder must still protect it.
        let r = try rule("drafts", ["paths": ["~/.foo/drafts"], "env_overrides": [["var": "FOO_DRAFTS"]]])
        let zones = DuplicateSearch.appFolders(for: [r], policy: policy, environment: ["FOO_DRAFTS": home.appendingPathComponent("Movies").path])
        XCTAssertTrue(zones.contains(home.appendingPathComponent("Movies")))
        let data = content(22)
        try write("Downloads/clip.mov", data)
        try write("Movies/My Draft/clip.mov", data)
        let found = try groups(search(["Downloads", "Movies"], appFolders: zones))
        let draft = try XCTUnwrap(found.first?.files.first { $0.url.path.contains("My Draft") })
        XCTAssertFalse(draft.canStay)
        XCTAssertNotNil(draft.viewOnly)
    }

    func testDataMovedOutByTheMainScreenIsStillAppData() throws {
        let data = content(23)
        try write("Downloads/large-v3.pt", data)
        try write("Downloads/Hoardless/whisper-models/whisper/large-v3.pt", data)
        let s = DuplicateSearch(roots: [home.appendingPathComponent("Downloads")], minimumSize: 1000,
                                ruleIDs: ["whisper-models"], policy: policy)
        let found = try groups(s)
        let moved = try XCTUnwrap(found.first?.files.first { $0.url.path.contains("/Hoardless/") })
        XCTAssertEqual(moved.viewOnly, .appFolder("~/Downloads/Hoardless/whisper-models"))
        XCTAssertFalse(moved.canStay, "a moved cache never counts as the copy that stays")
        let mine = try XCTUnwrap(found.first?.files.first { !$0.url.path.contains("/Hoardless/") })
        let out = actions.trashDuplicates([mine.url.path], in: found, search: s)
        XCTAssertEqual(out.failures.map(\.error), [.noCopyLeft], "the user's own copy is the last one that stays")
    }

    func testCopyEditedWhileInTheTrashIsNotTakenBackAsIdentical() throws {
        let a = try write("Downloads/a.bin", content(24))
        try write("Downloads/b.bin", content(24))
        let s = search(["Downloads"])
        let found = try groups(s)
        let out = actions.trashDuplicates([a.path], in: found, search: s)
        let record = try XCTUnwrap(out.records.first)
        var edited = content(24)
        edited[0] ^= 0xFF  // same size, different bytes
        try edited.write(to: record.now)
        try actions.undo(record)
        let old = try XCTUnwrap(found.first?.files.first { $0.url == a })
        XCTAssertNil(old.refreshed(), "an edit while in the Trash means it is no longer the same copy")
    }
}
