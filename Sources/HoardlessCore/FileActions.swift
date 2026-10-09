import Foundation

/// What happened to one location, kept so the user can undo it.
public struct ActionRecord: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable { case trashed, moved }

    public let id = UUID()
    public let kind: Kind
    public let ruleID: String
    public let locationID: String
    public let title: String
    /// Where it was.
    public let original: URL
    /// Where it is now (inside the Trash, or the folder the user picked).
    public let now: URL
    /// File system identity of the item at `now`, so Undo only ever puts back this exact item.
    let nowIdentity: [UInt64]?
    public let bytes: Int64
}

public enum ActionError: Error, Equatable, Sendable {
    public enum Destination: Sendable, Equatable { case notAFolder, notAllowedPlace, insideSource, linkInside }
    public enum Undo: Sendable, Equatable { case gone(String), occupied(String), unsafeOriginal, notSameItem }

    /// Protected, command-only, a linked or overridden location, or never measured.
    case notAllowed
    /// The folder on disk is no longer what was scanned (gone, replaced, or now a link).
    case changedSinceScan
    case badDestination(Destination)
    case undoBlocked(Undo)
    case trashNoLocation
    /// A move across drives stopped part way: the original was kept, a partial copy is at `leftover`.
    case partialMove(leftover: String, message: String)
    /// Trashing this duplicate would leave no unchanged copy of the file.
    case noCopyLeft
    case failed(String)
}

/// The only code in Hoardless that changes files. It trashes or moves exactly one scanned location at a time,
/// re-checks it on disk right before acting, and never deletes anything permanently (CLAUDE.md rules 1-5).
public struct FileActions: Sendable {
    public let policy: PathPolicy
    /// Moves an item to the Trash and returns where it landed. Replaceable in tests.
    let trasher: @Sendable (URL) throws -> URL

    public init(policy: PathPolicy = PathPolicy()) {
        self.init(policy: policy) { url in
            var landed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            guard let landed else { throw ActionError.trashNoLocation }
            return landed as URL
        }
    }

    init(policy: PathPolicy, trasher: @escaping @Sendable (URL) throws -> URL) {
        self.policy = policy
        self.trasher = trasher
    }

    // MARK: what may be acted on

    /// Only a measured, non-protected, non-command-only location that is exactly one of the rule's own paths,
    /// with no link anywhere below the home folder. Everything else is shown read-only.
    public func canAct(_ location: Location, in result: RuleResult) -> Bool {
        let rule = result.rule
        guard rule.safety != .protected, rule.commandOnly != true, location.origin == .rulePath,
              case .measured = result.states[location.id] ?? .notScanned,
              let literal = policy.expand(location.display) else { return false }
        return literal.standardizedFileURL.path == location.url.path
    }

    // MARK: actions

    public func trash(_ location: Location, of result: RuleResult) throws -> ActionRecord {
        let (url, bytes) = try prepare(location, of: result)
        let landed: URL
        do { landed = try trasher(url) } catch let error as ActionError { throw error } catch {
            throw ActionError.failed(error.localizedDescription)
        }
        return ActionRecord(kind: .trashed, ruleID: result.id, locationID: location.id, title: result.rule.title.en,
                            original: url, now: landed, nowIdentity: Self.identity(landed.path), bytes: bytes)
    }

    /// Where `move` would put the location inside `folder`: `<folder>/Hoardless/<rule id>/<name>`, plus " 2", " 3"…
    /// if that name is taken. Nil if the folder is not an allowed destination. Changes nothing.
    public func plannedTarget(for location: Location, of result: RuleResult, in folder: URL) -> URL? {
        guard let real = try? checkDestination(folder, source: location.url) else { return nil }
        return Self.freeName(in: real.appendingPathComponent("Hoardless").appendingPathComponent(result.id), for: location.url.lastPathComponent)
    }

    public func move(_ location: Location, of result: RuleResult, to folder: URL) throws -> ActionRecord {
        let (url, bytes) = try prepare(location, of: result)
        let real = try checkDestination(folder, source: url)
        let base = real.appendingPathComponent("Hoardless").appendingPathComponent(result.id)
        let fm = FileManager.default
        do { try fm.createDirectory(at: base, withIntermediateDirectories: true) } catch {
            throw ActionError.failed(error.localizedDescription)
        }
        // A pre-existing "Hoardless" or "<rule id>" link would send the data somewhere unchecked.
        guard base.resolvingSymlinksInPath().path == base.path else { throw ActionError.badDestination(.linkInside) }
        let target = Self.freeName(in: base, for: url.lastPathComponent)
        do { try fm.moveItem(at: url, to: target) } catch {
            if Self.exists(target.path) {
                throw ActionError.partialMove(leftover: target.path, message: error.localizedDescription)
            }
            throw ActionError.failed(error.localizedDescription)
        }
        return ActionRecord(kind: .moved, ruleID: result.id, locationID: location.id, title: result.rule.title.en,
                            original: url, now: target, nowIdentity: Self.identity(target.path), bytes: bytes)
    }

    /// Puts the item back where it was: only the same item, only if nothing has taken its place,
    /// and only if no folder above the original spot has become a link.
    public func undo(_ record: ActionRecord) throws {
        let fm = FileManager.default
        guard Self.exists(record.now.path) else { throw ActionError.undoBlocked(.gone(record.now.path)) }
        guard !Self.isLink(record.now.path), let id = record.nowIdentity, Self.identity(record.now.path) == id else {
            throw ActionError.undoBlocked(.notSameItem)
        }
        guard !Self.exists(record.original.path) else { throw ActionError.undoBlocked(.occupied(record.original.path)) }
        guard originalIsSafe(record.original) else { throw ActionError.undoBlocked(.unsafeOriginal) }
        do {
            try fm.createDirectory(at: record.original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: record.now, to: record.original)
        } catch {
            throw ActionError.failed(error.localizedDescription)
        }
        if record.kind == .moved { Self.removeEmptyMoveFolders(after: record) }
    }

    /// After a move is put back, removes the "Hoardless/<rule id>" folders the move made, but only while they are
    /// empty: rmdir cannot remove a folder that holds anything (another moved item, a file of the user's) or a link.
    private static func removeEmptyMoveFolders(after record: ActionRecord) {
        let ruleFolder = record.now.deletingLastPathComponent()
        let hoardless = ruleFolder.deletingLastPathComponent()
        guard ruleFolder.lastPathComponent == record.ruleID, hoardless.lastPathComponent == "Hoardless" else { return }
        if rmdir(ruleFolder.path) == 0 { _ = rmdir(hoardless.path) }
    }

    // MARK: checks

    /// Re-checks the location on disk right before acting, without trusting anything cached at scan time.
    private func prepare(_ location: Location, of result: RuleResult) throws -> (URL, Int64) {
        guard result.locations.contains(location), canAct(location, in: result),
              case .measured(let usage) = result.states[location.id] ?? .notScanned else { throw ActionError.notAllowed }
        let path = location.url.path
        guard Self.exists(path), !Self.isLink(path),
              case .success(let real) = policy.check(URL(fileURLWithPath: path)), real.path == path,
              let scanned = usage.identity, Self.identity(path) == scanned else { throw ActionError.changedSinceScan }
        return (URL(fileURLWithPath: path), usage.bytes)
    }

    /// An existing folder on a mounted volume, or in the home folder but not the home folder itself, the Trash,
    /// Library or an app cache/config folder; never inside the source.
    private func checkDestination(_ folder: URL, source: URL) throws -> URL {
        let real = folder.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real.path, isDirectory: &isDir), isDir.boolValue else {
            throw ActionError.badDestination(.notAFolder)
        }
        let parts = PathPolicy.fold(real.path)
        if parts.starts(with: PathPolicy.fold(source.path)) { throw ActionError.badDestination(.insideSource) }
        if parts.count >= 2 && parts[0] == "volumes" { return real }
        guard let rel = policy.relativeComponents(real), let top = rel.first,
              !["library", ".trash", ".cache", ".config", ".local"].contains(top) else {
            throw ActionError.badDestination(.notAllowedPlace)
        }
        return real
    }

    /// The nearest existing folder above `original` must be inside home and not be, or sit under, a link.
    private func originalIsSafe(_ original: URL) -> Bool {
        var probe = original.deletingLastPathComponent()
        while !Self.exists(probe.path) {
            let up = probe.deletingLastPathComponent()
            if up.path == probe.path { return false }
            probe = up
        }
        guard !Self.isLink(probe.path), probe.resolvingSymlinksInPath().path == probe.standardizedFileURL.path,
              policy.relativeComponents(probe) != nil else { return false }
        if case .success(let real) = policy.check(original), real.path == original.path { return true }
        return false
    }

    // MARK: file system helpers (lstat semantics: a link is never followed)

    static func exists(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)) != nil
    }

    static func isLink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    /// Volume number + file number of the item itself (not a link's target).
    public static func identity(_ path: String) -> [UInt64]? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let volume = (attrs[.systemNumber] as? NSNumber)?.uint64Value,
              let file = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        return [volume, file]
    }

    private static func freeName(in base: URL, for name: String) -> URL {
        var target = base.appendingPathComponent(name)
        var n = 2
        while exists(target.path) {
            target = base.appendingPathComponent("\(name) \(n)")
            n += 1
        }
        return target
    }
}
