import Foundation

/// One rule file from rules/apps: where one app keeps one kind of data. See docs/RULES.md.
public struct Rule: Decodable, Identifiable, Sendable {
    public struct Localized: Decodable, Sendable {
        public let en: String
        public let zh: String

        public func text(chinese: Bool) -> String { chinese ? zh : en }
    }

    public struct EnvOverride: Decodable, Sendable {
        public let `var`: String
        public let subpath: String?
    }

    public struct Cleanup: Decodable, Sendable {
        public let command: String
        public let source: String
    }

    public enum Safety: String, Decodable, Sendable {
        case safe, review, protected
    }

    public enum Category: String, Decodable, Sendable, CaseIterable {
        case aiModels = "ai-models"
        case packageCache = "package-cache"
        case videoEditors = "video-editors"
        case devTools = "dev-tools"
    }

    public let id: String
    public let app: String
    public let category: Category
    public let title: Localized
    public let explain: Localized
    public let paths: [String]
    public let envOverrides: [EnvOverride]?
    public let safety: Safety
    public let officialCleanup: Cleanup?
    public let commandOnly: Bool?
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, app, category, title, explain, paths, safety, status
        case envOverrides = "env_overrides"
        case officialCleanup = "official_cleanup"
        case commandOnly = "command_only"
    }

    public var isVerified: Bool { status == "verified" }
}

public enum RuleLoader {
    /// The rules shipped with the app: Contents/Resources/rules in a built .app, otherwise the package resource.
    public static func bundledRulesDirectory() -> URL? {
        if let url = Bundle.main.url(forResource: "rules", withExtension: nil) { return url }
        return Bundle.module.url(forResource: "rules", withExtension: nil)
    }

    /// Loads every *.json rule in `directory`. Unverified rules are left out unless asked for.
    public static func load(from directory: URL, includeUnverified: Bool = false) throws -> [Rule] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        return try files.map { try decoder.decode(Rule.self, from: Data(contentsOf: $0)) }
            .filter { includeUnverified || $0.isVerified }
    }
}
