import Foundation
import XCTest
@testable import HoardlessCore

/// Every test works in a throwaway folder that stands in for the home folder. Nothing outside it is touched.
final class HoardlessCoreTests: XCTestCase {
    private var root: URL!   // temp folder holding the fake home and an "outside" folder
    private var home: URL!
    private var outside: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("hoardless-tests-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)  // only the test's own temp folder
    }

    private func write(_ url: URL, bytes: Int) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    private func rule(paths: [String], env: [Rule.EnvOverride]? = nil) throws -> Rule {
        var json: [String: Any] = [
            "id": "t", "app": "T", "category": "package-cache", "title": ["en": "t", "zh": "t"],
            "explain": ["en": "e", "zh": "e"], "paths": paths, "safety": "review", "status": "verified",
        ]
        if let env { json["env_overrides"] = env.map { ["var": $0.var, "subpath": $0.subpath as Any].compactMapValues { $0 is NSNull ? nil : $0 } } }
        return try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func measuredUsage(_ state: LocationState, file: StaticString = #filePath, line: UInt = #line) -> Usage {
        guard case .measured(let usage) = state else { XCTFail("expected measured, got \(state)", file: file, line: line); return Usage() }
        return usage
    }

    // MARK: rules

    func testBundledRulesAllDecode() throws {
        let dir = try XCTUnwrap(RuleLoader.bundledRulesDirectory())
        let files = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        let rules = try RuleLoader.load(from: dir, includeUnverified: true)
        XCTAssertEqual(rules.count, files.count)
        XCTAssertGreaterThan(rules.count, 0)
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count)
    }

    // MARK: path policy

    func testExpandStaysInHome() {
        let policy = PathPolicy(home: home)
        XCTAssertNotNil(policy.expand("~/.cache/uv"))
        XCTAssertNil(policy.expand("/etc"))
        XCTAssertNil(policy.expand("~/../outside"))
        XCTAssertNil(policy.expand("~/"))
    }

    func testSymlinkOutOfHomeIsRejected() throws {
        let policy = PathPolicy(home: home)
        try fm.createDirectory(at: home.appendingPathComponent(".cache"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: home.appendingPathComponent(".cache/escape"), withDestinationURL: outside)
        let r = try rule(paths: ["~/.cache/escape"])
        let (accepted, rejected) = policy.locations(for: r, environment: [:])
        XCTAssertTrue(accepted.isEmpty)
        XCTAssertEqual(rejected.first?.reason, RejectionReason.outsideHome.rawValue)
    }

    func testWholeStandardFolderIsRejectedInAnyCase() throws {
        let policy = PathPolicy(home: home)
        for path in ["~/Movies", "~/movies", "~/Library/Caches", "~/.CACHE"] {
            let (accepted, rejected) = policy.locations(for: try rule(paths: [path]), environment: [:])
            XCTAssertTrue(accepted.isEmpty, path)
            XCTAssertEqual(rejected.first?.reason, RejectionReason.wholeStandardFolder.rawValue, path)
        }
    }

    func testProtectedFoldersNeedPermission() throws {
        let policy = PathPolicy(home: home)
        let (accepted, _) = policy.locations(for: try rule(paths: [
            "~/Documents/ComfyUI/models", "~/Library/Containers/com.x/Data/Documents/Models", "~/.cache/uv",
        ]), environment: [:])
        XCTAssertEqual(accepted.map(\.needsPermission), [true, true, false])
    }

    // MARK: environment overrides

    func testFirstSetVariableWinsAndRulePathsStay() throws {
        let policy = PathPolicy(home: home)
        let r = try rule(paths: ["~/.cache/uv"], env: [.init(var: "UV_CACHE_DIR", subpath: nil), .init(var: "XDG_CACHE_HOME", subpath: "uv")])
        let env = ["UV_CACHE_DIR": "", "XDG_CACHE_HOME": home.appendingPathComponent("xdg").path]
        let (accepted, _) = policy.locations(for: r, environment: env)
        XCTAssertEqual(accepted.map(\.display), ["~/.cache/uv", "$XDG_CACHE_HOME/uv"])
        XCTAssertEqual(accepted.last?.url.lastPathComponent, "uv")
    }

    func testOverrideOutsideHomeIsRejected() throws {
        let policy = PathPolicy(home: home)
        let r = try rule(paths: ["~/.cache/uv"], env: [.init(var: "UV_CACHE_DIR", subpath: nil)])
        let (accepted, rejected) = policy.locations(for: r, environment: ["UV_CACHE_DIR": outside.path])
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(rejected.first?.reason, RejectionReason.outsideHome.rawValue)
    }

    // MARK: scanning

    func testScanCountsFilesAndSkipsSymlinks() throws {
        let dir = home.appendingPathComponent(".cache/app")
        try write(dir.appendingPathComponent("a.bin"), bytes: 100_000)
        try write(dir.appendingPathComponent("sub/b.bin"), bytes: 50_000)
        try write(outside.appendingPathComponent("big.bin"), bytes: 2_000_000)
        try fm.createSymbolicLink(at: dir.appendingPathComponent("link-file"), withDestinationURL: outside.appendingPathComponent("big.bin"))
        try fm.createSymbolicLink(at: dir.appendingPathComponent("link-dir"), withDestinationURL: outside)

        let usage = measuredUsage(Scanner.measure(dir))
        XCTAssertEqual(usage.files, 2)
        XCTAssertEqual(usage.symlinks, 2)
        XCTAssertGreaterThanOrEqual(usage.bytes, 150_000)
        XCTAssertLessThan(usage.bytes, 1_000_000, "symlinked 2 MB file must not be counted")
    }

    func testHardLinksCountOnce() throws {
        let dir = home.appendingPathComponent(".cache/app")
        let file = dir.appendingPathComponent("a.bin")
        try write(file, bytes: 400_000)
        try fm.linkItem(at: file, to: dir.appendingPathComponent("a-link.bin"))
        let usage = measuredUsage(Scanner.measure(dir))
        XCTAssertEqual(usage.files, 1)
        XCTAssertLessThan(usage.bytes, 800_000)
    }

    func testMissingFolder() {
        XCTAssertEqual(Scanner.measure(home.appendingPathComponent("nope")), .missing)
    }

    func testScanDoesNotChangeAnything() throws {
        let dir = home.appendingPathComponent(".cache/app")
        try write(dir.appendingPathComponent("a.bin"), bytes: 10_000)
        let before = try fm.subpathsOfDirectory(atPath: root.path).sorted()
        let mtime = try fm.attributesOfItem(atPath: dir.appendingPathComponent("a.bin").path)[.modificationDate] as? Date
        _ = Scanner.measure(dir)
        XCTAssertEqual(try fm.subpathsOfDirectory(atPath: root.path).sorted(), before)
        XCTAssertEqual(try fm.attributesOfItem(atPath: dir.appendingPathComponent("a.bin").path)[.modificationDate] as? Date, mtime)
    }

    func testAutomaticScanSkipsPermissionFolders() async throws {
        let policy = PathPolicy(home: home)
        try write(home.appendingPathComponent("Documents/ComfyUI/models/m.bin"), bytes: 10_000)
        try write(home.appendingPathComponent(".cache/app/x.bin"), bytes: 10_000)
        let plan = ScanPlan.make(rules: [try rule(paths: ["~/Documents/ComfyUI/models", "~/.cache/app"])], policy: policy, environment: [:])
        let scanned = await ScanPlan.scanAutomatic(plan)
        let result = try XCTUnwrap(scanned.first)
        let states = result.locations.map { result.states[$0.id] }
        XCTAssertEqual(states.first, .needsPermission)
        XCTAssertGreaterThan(states.last??.bytes ?? 0, 0)
    }
}
