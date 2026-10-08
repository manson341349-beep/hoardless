import Foundation

/// A folder or file Hoardless may look at, after run-time safety checks.
public struct Location: Sendable, Hashable, Identifiable {
    public enum Origin: Sendable, Hashable {
        case rulePath
        case environment(String)
    }

    /// As written in the rule ("~/.cache/uv") or the variable that produced it ("$UV_CACHE_DIR").
    public let display: String
    /// Real path, symlinks resolved, guaranteed inside the home folder.
    public let url: URL
    public let origin: Origin
    /// Reading it may make macOS ask for permission (Documents, other apps' sandboxes…), so only on request.
    public let needsPermission: Bool

    public var id: String { url.path }
}

/// A location that was found but must not be used, with the reason.
public struct RejectedLocation: Sendable, Hashable {
    public let display: String
    public let path: String
    public let reason: String
}

/// Run-time copy of the rules in CLAUDE.md: only inside the home folder, never a whole standard folder,
/// symlinks resolved before checking. The rule validator checks rule files; this checks what is really on disk.
public struct PathPolicy: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static let wholeFolders: Set<[String]> = Set([
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Library", "Applications",
        "Library/Caches", "Library/Application Support", "Library/Containers", "Library/Group Containers",
        ".cache", ".config", ".local", ".local/share", ".Trash",
    ].map(PathPolicy.fold))

    private static let permissionPrefixes: [[String]] = [
        "Desktop", "Documents", "Downloads", "Library/Containers", "Library/Group Containers",
        "Library/Mobile Documents", "Library/CloudStorage",
    ].map(PathPolicy.fold)

    /// Case-insensitive, Unicode-normalized path components, as the home volume compares them.
    static func fold(_ relative: String) -> [String] {
        relative.decomposedStringWithCanonicalMapping.lowercased().split(separator: "/").map(String.init)
    }

    /// Components below the home folder, or nil if the URL is not inside it.
    func relativeComponents(_ url: URL) -> [String]? {
        let homeParts = Self.fold(home.path)
        let parts = Self.fold(url.standardizedFileURL.path)
        guard parts.count >= homeParts.count, Array(parts.prefix(homeParts.count)) == homeParts else { return nil }
        return Array(parts.dropFirst(homeParts.count))
    }

    /// "~/x/y" -> URL inside home. Anything else is refused.
    public func expand(_ tildePath: String) -> URL? {
        guard tildePath.hasPrefix("~/") else { return nil }
        let rest = tildePath.dropFirst(2).split(separator: "/").map(String.init)
        guard !rest.isEmpty, !rest.contains(".."), !rest.contains(".") else { return nil }
        return rest.reduce(home) { $0.appendingPathComponent($1) }
    }

    /// Resolves symlinks and checks the result. Returns the real URL or why it is refused.
    public func check(_ url: URL) -> Result<URL, RejectionReason> {
        let real = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let rel = relativeComponents(real) else { return .failure(.outsideHome) }
        if rel.isEmpty { return .failure(.wholeHome) }
        if Self.wholeFolders.contains(rel) { return .failure(.wholeStandardFolder) }
        return .success(real)
    }

    public func needsPermission(_ url: URL) -> Bool {
        guard let rel = relativeComponents(url) else { return true }
        return Self.permissionPrefixes.contains { rel.starts(with: $0) }
    }

    /// Every place to look for one rule: its own paths (always, so a legacy folder is never hidden) plus the
    /// first environment override that is set. Locations that fail the checks are returned as rejected.
    public func locations(for rule: Rule, environment: [String: String]) -> (accepted: [Location], rejected: [RejectedLocation]) {
        var accepted: [Location] = []
        var rejected: [RejectedLocation] = []

        func add(_ display: String, _ url: URL, _ origin: Location.Origin) {
            switch check(url) {
            case .success(let real):
                guard !accepted.contains(where: { $0.url == real }) else { return }
                accepted.append(Location(display: display, url: real, origin: origin, needsPermission: needsPermission(real)))
            case .failure(let reason):
                rejected.append(RejectedLocation(display: display, path: url.path, reason: reason.rawValue))
            }
        }

        for path in rule.paths {
            if let url = expand(path) {
                add(path, url, .rulePath)
            } else {
                rejected.append(RejectedLocation(display: path, path: path, reason: RejectionReason.notHomeRelative.rawValue))
            }
        }
        if let override = rule.envOverrides?.first(where: { !(environment[$0.var] ?? "").isEmpty }),
           let value = environment[override.var] {
            var url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            if let sub = override.subpath { url.appendPathComponent(sub) }
            let display = "$" + override.var + (override.subpath.map { "/" + $0 } ?? "")
            add(display, url, .environment(override.var))
        }
        return (accepted, rejected)
    }
}

public enum RejectionReason: String, Error, Sendable {
    case outsideHome = "outside the home folder"
    case wholeHome = "the whole home folder"
    case wholeStandardFolder = "a whole standard folder"
    case notHomeRelative = "not a ~/ path"
}
