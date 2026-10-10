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
    /// A move to another drive copies, then sends the original to the Trash: where it landed there, and its identity.
    /// Undo takes it back out of the Trash instead of copying everything back.
    var trashedOriginal: URL? = nil
    var trashedOriginalIdentity: [UInt64]? = nil
    /// What the copy on the other drive looked like right after the move, to notice files added to it later.
    var copyDigest: Int? = nil
}

public enum ActionError: Error, Equatable, Sendable {
    public enum Destination: Sendable, Equatable { case notAFolder, notAllowedPlace, insideSource, linkInside, insideAppData }
    public enum Undo: Sendable, Equatable { case gone(String), occupied(String), unsafeOriginal, notSameItem }

    /// Protected, command-only, a linked or overridden location, or never measured.
    case notAllowed
    /// Another location (of another rule, a setting or a variable) sits inside this one; acting on it would take
    /// that along without the confirmation naming it.
    case holdsOtherLocation(String)
    /// The folder on disk is no longer what was scanned (gone, replaced, or now a link).
    case changedSinceScan
    case badDestination(Destination)
    case undoBlocked(Undo)
    case trashNoLocation
    /// Copying to another drive did not finish. The original was not touched; `leftover` is the incomplete copy
    /// if it could not be sent to that drive's Trash.
    case copyIncomplete(leftover: String?, message: String)
    /// Something was written into the folder while it was being copied (the app may still be running). Nothing was
    /// moved; `leftover` as above.
    case changedWhileCopying(leftover: String?)
    /// The copy on the other drive was complete, but the original could not be sent to the Trash, so the move was
    /// undone. `copy` is the complete copy if it could not be sent to that drive's Trash (two full copies exist).
    case originalKept(copy: String?, message: String)
    /// After the copy was made, the original was replaced or disappeared, so it was not sent to the Trash. The
    /// complete copy was kept at `copy`.
    case originalChanged(copy: String)
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
    /// Copies an item to a new path (used only for moves to another drive). Replaceable in tests.
    let copier: @Sendable (URL, URL) throws -> Void
    /// Tests only: treat every move as a move to another drive.
    let alwaysCopy: Bool

    public init(policy: PathPolicy = PathPolicy()) {
        self.init(policy: policy) { url in
            var landed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            guard let landed else { throw ActionError.trashNoLocation }
            return landed as URL
        }
    }

    init(policy: PathPolicy, trasher: @escaping @Sendable (URL) throws -> URL,
         copier: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
         alwaysCopy: Bool = false) {
        self.policy = policy
        self.trasher = trasher
        self.copier = copier
        self.alwaysCopy = alwaysCopy
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
        if !alwaysCopy, Self.sameVolume(url, base) {
            // One rename on the same drive: it either happens completely or not at all.
            do { try fm.moveItem(at: url, to: target) } catch { throw ActionError.failed(error.localizedDescription) }
            return ActionRecord(kind: .moved, ruleID: result.id, locationID: location.id, title: result.rule.title.en,
                                original: url, now: target, nowIdentity: Self.identity(target.path), bytes: bytes)
        }
        // Another drive. Foundation's own move would copy, then delete the original and could stop half way through
        // deleting it. Instead: copy, check the copy, then send the original to the Trash. It is never deleted.
        let identity = Self.identity(url.path)
        let before = try copyChecked(url, to: target)
        guard Self.exists(url.path), !Self.isLink(url.path), Self.identity(url.path) == identity else {
            throw ActionError.originalChanged(copy: target.path)
        }
        // Checked once more right before the Trash: anything written meanwhile would be missing from the copy.
        guard Self.snapshot(url) == before else { throw ActionError.changedWhileCopying(leftover: trashOrKeep(target)) }
        let copyDigest = Self.digest(target)
        let landed: URL
        do { landed = try trasher(url) } catch {
            throw ActionError.originalKept(copy: trashOrKeep(target), message: error.localizedDescription)
        }
        return ActionRecord(kind: .moved, ruleID: result.id, locationID: location.id, title: result.rule.title.en,
                            original: url, now: target, nowIdentity: Self.identity(target.path), bytes: bytes,
                            trashedOriginal: landed, trashedOriginalIdentity: Self.identity(landed.path), copyDigest: copyDigest)
    }

    /// Copies `source` to `target` under a temporary " (incomplete)" name next to it, checks that every file arrived
    /// and that nothing in the source changed meanwhile, then gives the copy its real name. On any problem the
    /// partial copy is sent to the Trash (or reported if that fails) and the source is never touched.
    @discardableResult
    private func copyChecked(_ source: URL, to target: URL) throws -> [String: String] {
        let tag = UUID().uuidString.prefix(6).lowercased()
        let staging = Self.freeName(in: target.deletingLastPathComponent(), for: target.lastPathComponent + " (incomplete \(tag))")
        let before = Self.snapshot(source)
        do { try copier(source, staging) } catch {
            throw ActionError.copyIncomplete(leftover: Self.exists(staging.path) ? trashOrKeep(staging) : nil,
                                             message: error.localizedDescription)
        }
        guard let before, let after = Self.snapshot(source), before == after else {
            throw ActionError.changedWhileCopying(leftover: trashOrKeep(staging))
        }
        guard let copied = Self.snapshot(staging), Self.sameContentShape(before, copied) else {
            throw ActionError.copyIncomplete(leftover: trashOrKeep(staging), message: "")
        }
        do { try FileManager.default.moveItem(at: staging, to: target) } catch {
            throw ActionError.copyIncomplete(leftover: trashOrKeep(staging), message: error.localizedDescription)
        }
        return before
    }

    /// Sends a copy Hoardless made to the Trash; returns its path only if that failed and it is still there.
    private func trashOrKeep(_ url: URL) -> String? {
        if (try? trasher(url)) != nil { return nil }
        return Self.exists(url.path) ? url.path : nil
    }

    /// Puts the item back where it was: only the same item, only if nothing has taken its place,
    /// and only if no folder above the original spot has become a link.
    public func undo(_ record: ActionRecord) throws {
        let fm = FileManager.default
        if let trashed = record.trashedOriginal {
            try undoCopiedMove(record, trashed: trashed)
            return
        }
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

    /// Undo of a move to another drive: the original is taken back out of the Trash (one rename, nothing copied),
    /// then the copy on the other drive goes to that drive's Trash. If the original is no longer in the Trash, the
    /// copy is copied back the same careful way as the move.
    private func undoCopiedMove(_ record: ActionRecord, trashed: URL) throws {
        guard !Self.exists(record.original.path) else { throw ActionError.undoBlocked(.occupied(record.original.path)) }
        guard originalIsSafe(record.original) else { throw ActionError.undoBlocked(.unsafeOriginal) }
        let fm = FileManager.default
        // Files added to the copy since the move (a model downloaded there) would be lost by taking the old original
        // back; then the copy as it is now is copied back instead.
        let copyChanged = Self.exists(record.now.path) && Self.digest(record.now) != record.copyDigest
        if !copyChanged, Self.exists(trashed.path), !Self.isLink(trashed.path), let id = record.trashedOriginalIdentity,
           Self.identity(trashed.path) == id {
            do {
                try fm.createDirectory(at: record.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: trashed, to: record.original)
            } catch {
                throw ActionError.failed(error.localizedDescription)
            }
        } else {
            guard Self.exists(record.now.path) else { throw ActionError.undoBlocked(.gone(record.now.path)) }
            guard !Self.isLink(record.now.path), let id = record.nowIdentity, Self.identity(record.now.path) == id else {
                throw ActionError.undoBlocked(.notSameItem)
            }
            do { try fm.createDirectory(at: record.original.deletingLastPathComponent(), withIntermediateDirectories: true) } catch {
                throw ActionError.failed(error.localizedDescription)
            }
            try copyChecked(record.now, to: record.original)
        }
        // The copy on the other drive is no longer needed; it goes to that drive's Trash, never deleted.
        if Self.exists(record.now.path), let id = record.nowIdentity, Self.identity(record.now.path) == id {
            _ = try? trasher(record.now)
        }
        Self.removeEmptyMoveFolders(after: record)
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

    /// An existing ordinary folder: in the home folder (not the home folder itself, Library, or any hidden, cache or
    /// "User Data" folder), or on another mounted drive (not a hidden folder such as its Trash); never inside the
    /// source. The home-folder rules apply first, so a home folder on an external drive gets them too.
    private func checkDestination(_ folder: URL, source: URL) throws -> URL {
        let real = folder.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real.path, isDirectory: &isDir), isDir.boolValue else {
            throw ActionError.badDestination(.notAFolder)
        }
        let parts = PathPolicy.fold(real.path)
        if parts.starts(with: PathPolicy.fold(source.path)) { throw ActionError.badDestination(.insideSource) }
        func ordinary(_ names: ArraySlice<String>) -> Bool {
            !names.contains { $0.hasPrefix(".") || ["cache", "caches", "user data"].contains($0) }
        }
        if let rel = policy.relativeComponents(real) {
            guard let top = rel.first, top != "library", ordinary(rel[...]) else { throw ActionError.badDestination(.notAllowedPlace) }
            return real
        }
        guard parts.count >= 2, parts[0] == "volumes", ordinary(parts.dropFirst()) else {
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

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        guard let x = identity(a.path)?.first, let y = identity(b.path)?.first else { return false }
        return x == y
    }

    /// A fingerprint of everything below `root` (kinds, sizes, modification times); nil if unreadable.
    static func digest(_ root: URL) -> Int? {
        guard let snap = snapshot(root) else { return nil }
        var hasher = Hasher()
        for (key, value) in snap.sorted(by: { $0.key < $1.key }) { hasher.combine(key); hasher.combine(value) }
        return hasher.finalize()
    }

    /// Every entry below `root` (links not followed): its kind, size and modification time. Nil if unreadable.
    static func snapshot(_ root: URL) -> [String: String]? {
        let fm = FileManager.default
        var out: [String: String] = [:]
        var stack: [String] = [""]
        while let rel = stack.popLast() {
            let path = rel.isEmpty ? root.path : root.path + "/" + rel
            guard let attrs = try? fm.attributesOfItem(atPath: path), let type = attrs[.type] as? FileAttributeType else { return nil }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            switch type {
            case .typeDirectory:
                out[rel] = "d"
                guard let names = try? fm.contentsOfDirectory(atPath: path) else { return nil }
                for name in names { stack.append(rel.isEmpty ? name : rel + "/" + name) }
            case .typeSymbolicLink:
                out[rel] = "l:" + ((try? fm.destinationOfSymbolicLink(atPath: path)) ?? "?")
            default:
                out[rel] = "f:\(size):\(mtime)"
            }
        }
        return out
    }

    /// The copy has exactly the same entries as the source, of the same kind and size (times may differ). Extra
    /// "._name" files that drives without extended attributes (exFAT, FAT) add, and a ".DS_Store" the Finder writes if
    /// the folder is opened while copying, are ignored.
    static func sameContentShape(_ source: [String: String], _ copy: [String: String]) -> Bool {
        func shape(_ v: String) -> String { v.hasPrefix("f:") ? String(v.split(separator: ":")[1]) : v }
        let extra = copy.keys.filter { source[$0] == nil }
        guard extra.allSatisfy({ name in
            let last = name.split(separator: "/").last ?? ""
            return last.hasPrefix("._") || last == ".DS_Store"
        }) else { return false }
        return source.allSatisfy { key, value in copy[key].map(shape) == shape(value) }
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
