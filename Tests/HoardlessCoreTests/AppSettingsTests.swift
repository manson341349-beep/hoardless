import Foundation
import SQLite3
import XCTest
@testable import HoardlessCore

/// Settings files are written into a throwaway fake home; nothing real is read.
final class AppSettingsTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("hoardless-settings-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)  // only this test's temp folder
    }

    private func write(_ relative: String, _ text: String) throws {
        let url = home.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func folder(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func rule(paths: [String], settings: [[String: String]]) throws -> Rule {
        let json: [String: Any] = [
            "id": "r", "app": "T", "category": "ai-models", "title": ["en": "t", "zh": "t"], "explain": ["en": "e", "zh": "e"],
            "paths": paths, "safety": "review", "status": "verified", "app_settings": settings,
        ]
        return try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func locations(_ rule: Rule) -> (accepted: [Location], rejected: [RejectedLocation]) {
        PathPolicy(home: home).locations(for: rule, environment: [:])
    }

    func testIniJsonPointerAndSqliteAllResolve() throws {
        let cache = try folder("Movies/Editor/MyCache")
        let models = try folder("Models/lm")
        let shared = try folder("Shared/comfy")
        let pointed = try folder("LMHome")
        try folder("LMHome/models")
        let ollama = try folder("Big/ollama")
        try write("Movies/Editor/Config/globalSetting", "[General]\nother=1\ncurrentCachePath=\(cache.path)\n")
        try write(".lm/settings.json", #"{"downloadsFolder": "\#(models.path)", "x": 1}"#)
        try write("Library/Application Support/Comfy/settings.json", #"{"modelsDirs": ["\#(shared.path)", ""]}"#)
        try write(".lm-home-pointer", pointed.path + "\n")
        try makeSqlite("Library/Application Support/Ollama/db.sqlite", models: ollama.path)

        let r = try rule(paths: ["~/.cache/none"], settings: [
            ["file": "~/Movies/Editor/Config/globalSetting", "format": "ini", "key": "General.currentCachePath"],
            ["file": "~/.lm/settings.json", "format": "json", "key": "downloadsFolder"],
            ["file": "~/Library/Application Support/Comfy/settings.json", "format": "json", "key": "modelsDirs"],
            ["file": "~/.lm-home-pointer", "format": "pointer", "subpath": "models"],
            ["file": "~/Library/Application Support/Ollama/db.sqlite", "format": "sqlite", "key": "settings.models"],
        ])
        let found = Set(locations(r).accepted.filter { if case .appSetting = $0.origin { return true }; return false }.map(\.url.path))
        XCTAssertEqual(found, [cache.path, models.path, shared.path, pointed.appendingPathComponent("models").path, ollama.path])
    }

    func testSettingsLocationsAreNeverActionable() async throws {
        let moved = try folder("Moved/cache")
        try Data(repeating: 1, count: 10_000).write(to: moved.appendingPathComponent("x.bin"))
        try write(".app/conf.ini", "[General]\ncache=\(moved.path)\n")
        let r = try rule(paths: ["~/.cache/none"], settings: [["file": "~/.app/conf.ini", "format": "ini", "key": "General.cache"]])
        let plan = ScanPlan.make(rules: [r], policy: PathPolicy(home: home), environment: [:])
        let result = await ScanPlan.scanAutomatic(plan)[0]
        let loc = try XCTUnwrap(result.locations.first { $0.url.path == moved.path })
        guard case .measured = result.states[loc.id] else { return XCTFail("must be measured, or this proves nothing") }
        XCTAssertFalse(FileActions(policy: PathPolicy(home: home)).canAct(loc, in: result))
    }

    func testLocationOutsideHomeIsListedNotMeasured() throws {
        try write(".app/conf.ini", "[General]\ncache=/Volumes/External/cache\n")
        let r = try rule(paths: ["~/.cache/none"], settings: [["file": "~/.app/conf.ini", "format": "ini", "key": "General.cache"]])
        let (accepted, rejected) = locations(r)
        XCTAssertFalse(accepted.contains { $0.url.path.hasPrefix("/Volumes") })
        XCTAssertEqual(rejected.first?.kind, .outsideHome)
        XCTAssertEqual(rejected.first?.path, "/Volumes/External/cache")
    }

    func testValueEqualToRulePathStaysOneActionableLocation() throws {
        let cache = try folder(".cache/app")
        try write(".app/conf.ini", "[General]\ncache=\(cache.path)\n")
        let r = try rule(paths: ["~/.cache/app"], settings: [["file": "~/.app/conf.ini", "format": "ini", "key": "General.cache"]])
        let accepted = locations(r).accepted
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(accepted.first?.origin, .rulePath)
    }

    func testMissingBrokenOrWrongSectionYieldsNothing() throws {
        try write(".app/bad.json", "{not json")
        try write(".app/conf.ini", "[Other]\ncache=/Users/x\n")
        try write(".app/big.ini", "[General]\ncache=/x\n" + String(repeating: "#", count: AppSettings.maxTextSize))
        let policy = PathPolicy(home: home)
        func setting(_ file: String, _ format: String, _ key: String?) throws -> Rule.AppSetting {
            var dict = ["file": file, "format": format]
            if let key { dict["key"] = key }
            return try JSONDecoder().decode(Rule.AppSetting.self, from: JSONSerialization.data(withJSONObject: dict))
        }
        XCTAssertEqual(AppSettings.paths(for: try setting("~/.app/missing.ini", "ini", "General.cache"), policy: policy), [])
        XCTAssertEqual(AppSettings.paths(for: try setting("~/.app/bad.json", "json", "x"), policy: policy), [])
        XCTAssertEqual(AppSettings.paths(for: try setting("~/.app/conf.ini", "ini", "General.cache"), policy: policy), [])
        XCTAssertEqual(AppSettings.paths(for: try setting("~/.app/big.ini", "ini", "General.cache"), policy: policy), [], "oversized files are not read")
    }

    func testSqliteRefusesUnsafeNamesAndOpensReadOnly() throws {
        try makeSqlite("db.sqlite", models: "/tmp/x")
        let db = home.appendingPathComponent("db.sqlite")
        XCTAssertEqual(AppSettings.sqlite(db, key: "settings.models"), "/tmp/x")
        XCTAssertNil(AppSettings.sqlite(db, key: "settings.models; DROP TABLE settings"))
        XCTAssertNil(AppSettings.sqlite(db, key: "settings"))
        XCTAssertEqual(AppSettings.sqlite(db, key: "settings.models"), "/tmp/x", "table still there")
        let before = try fm.attributesOfItem(atPath: db.path)[.modificationDate] as? Date
        _ = AppSettings.sqlite(db, key: "settings.models")
        XCTAssertEqual(try fm.attributesOfItem(atPath: db.path)[.modificationDate] as? Date, before)
    }

    private func makeSqlite(_ relative: String, models: String) throws {
        let url = home.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = "CREATE TABLE settings (id INTEGER PRIMARY KEY, models TEXT NOT NULL DEFAULT ''); INSERT INTO settings (id, models) VALUES (1, '\(models)');"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }
}
