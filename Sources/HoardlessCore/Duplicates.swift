import CryptoKit
import Darwin
import Foundation

/// One copy of a file that exists more than once.
public struct DuplicateFile: Sendable, Hashable, Identifiable {
    public enum ViewOnly: Sendable, Hashable {
        /// Inside an app's own data (a folder a Hoardless rule knows, "User Data", a cache or a hidden folder).
        case appFolder(String)
        /// Inside a git work tree: removing it would change the project.
        case codeRepository
        /// Inside a Python environment or a package folder such as node_modules.
        case toolFolder
        /// Hard-linked elsewhere: trashing this name frees nothing.
        case hardLinked
    }

    /// Real path (no link anywhere in it below the search folder).
    public let url: URL
    public let size: Int64
    /// Volume and file number, checked again right before trashing.
    public let identity: [UInt64]
    public let modified: Date
    /// Status-change time. Unlike the modification time, programs cannot set it back, so it catches in-place edits.
    public let changed: Date
    /// Space only this copy uses on disk. APFS clones share space, so this can be far below `size`.
    public let freeable: Int64
    /// Set when this copy may be shown but never trashed.
    public let viewOnly: ViewOnly?
    /// In iCloud Drive (for example a synced Desktop or Documents): trashing it removes it from other devices too.
    public let inICloud: Bool

    public var id: String { url.path }

    /// Whether this copy can be counted on to still exist later. A copy in an app's data cannot: the app may clean it,
    /// or the user may trash that cache from Hoardless's main screen.
    public var canStay: Bool { Self.stays(viewOnly) }

    static func stays(_ reason: ViewOnly?) -> Bool {
        if case .appFolder? = reason { return false }
        return true
    }

    /// The same copy as it is on disk now (after Undo put it back), or nil if it is no longer the same file.
    public func refreshed() -> DuplicateFile? {
        guard let now = FileStamp(url.path), now.isRegular, now.identity == identity, now.size == size else { return nil }
        return DuplicateFile(url: url, size: size, identity: identity, modified: now.modified, changed: now.changed,
                             freeable: freeable, viewOnly: viewOnly, inICloud: inICloud)
    }
}

/// What lstat says about one path; a link is never followed.
struct FileStamp: Equatable {
    let identity: [UInt64]
    let size: Int64
    let modified: Date
    let changed: Date
    let links: UInt16
    let isRegular: Bool
    let isDirectory: Bool
    let dataless: Bool
    let device: Int32

    init?(_ path: String) {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        identity = [UInt64(UInt32(bitPattern: st.st_dev)), UInt64(st.st_ino)]
        size = Int64(st.st_size)
        modified = Self.date(st.st_mtimespec)
        changed = Self.date(st.st_ctimespec)
        links = st.st_nlink
        isRegular = st.st_mode & S_IFMT == S_IFREG
        isDirectory = st.st_mode & S_IFMT == S_IFDIR
        dataless = st.st_flags & UInt32(SF_DATALESS) != 0
        device = st.st_dev
    }

    static func date(_ t: timespec) -> Date { Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9) }
}

/// Files with byte-for-byte the same content (same size, same SHA-256).
public struct DuplicateGroup: Sendable, Identifiable, Hashable {
    public let digest: String
    public let size: Int64
    public var files: [DuplicateFile]

    public var id: String { digest }
    /// Most space the Trash could get back here while one copy that can stay is left: every copy that may be picked,
    /// except the cheapest one when no view-only copy that can stay is there anyway.
    public var wasted: Int64 {
        let pickable = files.filter { $0.viewOnly == nil }.map(\.freeable)
        guard !pickable.isEmpty else { return 0 }
        let total = pickable.reduce(0, +)
        return files.contains(where: { $0.viewOnly != nil && $0.canStay }) ? total : total - (pickable.min() ?? 0)
    }

    /// A copy may be picked only if it is not view-only and another copy that can stay (see `canStay`) is not picked.
    public func canSelect(_ file: DuplicateFile, alreadySelected: Set<String>) -> Bool {
        guard file.viewOnly == nil, files.contains(file) else { return false }
        if alreadySelected.contains(file.id) { return true }
        return files.contains { $0.id != file.id && $0.canStay && !alreadySelected.contains($0.id) }
    }

    /// The app's "Keep One": everything that may be picked except the suggested keeper, which is never picked.
    public func keepingOne(current: Set<String>) -> Set<String> {
        var picked = current
        for f in files { picked.remove(f.id) }
        guard let keeper = suggestedKeeper else { return picked }
        for f in files where f.id != keeper.id && canSelect(f, alreadySelected: picked) { picked.insert(f.id) }
        return picked
    }

    /// The copy to keep when the user asks to "keep one": a view-only copy that can stay if there is one (it stays
    /// anyway), otherwise the oldest copy that may be picked. Never a copy in an app's data.
    public var suggestedKeeper: DuplicateFile? {
        files.first { $0.viewOnly != nil && $0.canStay }
            ?? files.filter { $0.viewOnly == nil }.min { $0.modified < $1.modified }
    }
}

/// Where to look, after checks: folders the user picked, inside the home folder.
public struct DuplicateSearch: Sendable {
    public enum RootProblem: Error, Equatable, Sendable { case outsideHome, wholeHome, library, trash, notAFolder, insidePackage, otherVolume }

    public let roots: [URL]
    /// Smaller files are ignored: they free little space and make the list long.
    public let minimumSize: Int64
    /// Apps' own folders (see `appFolders(for:)`); copies inside them are view-only.
    public let appFolders: [URL]
    public let policy: PathPolicy
    /// Folders the user asked for that failed `checkRoot`, with the reason.
    public let refused: [(url: URL, problem: RootProblem)]

    /// Media libraries that macOS apps manage outside a package (TV and Music copy imported files here).
    static let builtInAppFolders = ["Movies/TV", "Music/Music", "Music/iTunes"]

    public init(roots: [URL], minimumSize: Int64 = 1_000_000, appFolders: [URL] = [], policy: PathPolicy = PathPolicy()) {
        self.policy = policy
        self.minimumSize = minimumSize
        self.appFolders = (appFolders + Self.builtInAppFolders.map { policy.home.appendingPathComponent($0) })
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        // Resolve links, drop folders already inside another one; keep the reason for each refused folder.
        var real: [URL] = [], refused: [(url: URL, problem: RootProblem)] = []
        for root in roots {
            switch Self.checkRoot(root, policy: policy) {
            case .success(let url): real.append(url)
            case .failure(let problem): refused.append((root, problem))
            }
        }
        self.refused = refused
        self.roots = real.filter { r in !real.contains { $0 != r && Self.isInside(r, $0) } }
            .reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// A folder the user may search: an existing folder in the home folder, not the home folder itself,
    /// not Library (app data, iCloud Drive, other apps' sandboxes) and not the Trash.
    public static func checkRoot(_ url: URL, policy: PathPolicy) -> Result<URL, RootProblem> {
        let real = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let rel = policy.relativeComponents(real) else { return .failure(.outsideHome) }
        guard let top = rel.first else { return .failure(.wholeHome) }
        if top == "library" { return .failure(.library) }
        if top == ".trash" { return .failure(.trash) }
        guard let stamp = FileStamp(real.path), stamp.isDirectory else { return .failure(.notAFolder) }
        if stamp.device != FileStamp(policy.home.path)?.device { return .failure(.otherVolume) }
        var dir = real
        while let rel = policy.relativeComponents(dir), !rel.isEmpty {
            if isPackage(dir) { return .failure(.insidePackage) }
            dir.deleteLastPathComponent()
        }
        return .success(real)
    }

    /// An app, a Photos or Final Cut library…: a folder Finder shows as one file.
    static func isPackage(_ url: URL) -> Bool {
        (try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }

    /// Folders whose presence marks a code repository (git work trees may use a .git file instead).
    static let repositoryMarkers = [".git", ".hg", ".svn"]

    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let parts = PathPolicy.fold(url.path), base = PathPolicy.fold(folder.path)
        return parts.count >= base.count && Array(parts.prefix(base.count)) == base
    }

    public func isSearched(_ url: URL) -> Bool { roots.contains { Self.isInside(url, $0) } }

    /// The whole folder each app keeps its data in, from the rules' locations: a rule path like
    /// ~/Movies/CapCut/User Data/Cache/effect protects all of ~/Movies/CapCut, and ~/.cache/huggingface/hub all of
    /// ~/.cache. Folders read from settings or environment variables are the user's own choice, so only they count.
    public static func appFolders(for locations: [Location], policy: PathPolicy) -> [URL] {
        let standard: Set<String> = ["desktop", "documents", "downloads", "movies", "music", "pictures"]
        var out: [URL] = []
        for loc in locations {
            var folder = loc.url
            if loc.origin == .rulePath, let rel = policy.relativeComponents(loc.url), let top = rel.first, top != "library" {
                let keep = standard.contains(top) ? 2 : 1
                if rel.count > keep {
                    folder = loc.url
                    for _ in 0..<(rel.count - keep) { folder.deleteLastPathComponent() }
                }
            }
            if !out.contains(folder) { out.append(folder) }
        }
        return out
    }

    /// Folder names that mean "an app's data" wherever they appear.
    static let appDataNames: Set<String> = ["user data", "cache", "caches"]

    /// Why a copy at `url` may only be shown, worked out from the disk as it is now; nil if it may be picked.
    public func viewOnlyReason(_ url: URL) -> DuplicateFile.ViewOnly? {
        if let zone = appFolders.first(where: { Self.isInside(url, $0) }) { return .appFolder(policy.tilde(zone)) }
        let fm = FileManager.default
        var dir = url.deletingLastPathComponent()
        while let rel = policy.relativeComponents(dir), !rel.isEmpty {
            let name = dir.lastPathComponent
            let folded = PathPolicy.fold(name).first ?? ""
            if folded.hasPrefix(".") || Self.appDataNames.contains(folded) || Self.isPackage(dir) { return .appFolder(policy.tilde(dir)) }
            if DuplicateFinder.skippedFolderNames.contains(name) || DuplicateFinder.isEnvironment(dir) { return .toolFolder }
            if Self.repositoryMarkers.contains(where: { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }) { return .codeRepository }
            dir.deleteLastPathComponent()
        }
        // A repository at the home folder itself (a dotfiles repo) is not counted: it would make every file view-only.
        if let stamp = FileStamp(url.path), stamp.links > 1 { return .hardLinked }
        return nil
    }
}

/// Read-only: lists, reads and hashes files; never changes anything.
public enum DuplicateFinder {
    public enum Event: Sendable {
        /// Still walking the folders.
        case listing(filesSeen: Int)
        /// Comparing contents of files that have the same size.
        case comparing(bytesDone: Int64, bytesTotal: Int64)
        case finished(groups: [DuplicateGroup], skipped: Skipped)
    }

    /// Things left out on purpose, so the UI can say so.
    public struct Skipped: Sendable, Equatable {
        /// iCloud files not downloaded to this Mac (reading them would download them).
        public var notDownloaded = 0
        public var unreadable = 0
        public init() {}
    }

    struct Candidate {
        let url: URL
        let size: Int64
        let identity: [UInt64]
        let modified: Date
        let changed: Date
        let links: UInt16
    }

    /// Folders whose contents belong to a tool: never looked inside.
    static let skippedFolderNames: Set<String> = ["node_modules", "site-packages", "__pycache__", "dist-packages"]

    public static func events(_ search: DuplicateSearch) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let result = run(search, report: { continuation.yield($0) }, isCancelled: { Task.isCancelled })
                if let result { continuation.yield(.finished(groups: result.0, skipped: result.1)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Same search, returned at once (nil if cancelled).
    public static func find(_ search: DuplicateSearch, isCancelled: @Sendable () -> Bool = { false }) -> ([DuplicateGroup], Skipped)? {
        run(search, report: { _ in }, isCancelled: isCancelled)
    }

    static func run(_ search: DuplicateSearch, report: (Event) -> Void, isCancelled: () -> Bool) -> ([DuplicateGroup], Skipped)? {
        var skipped = Skipped()
        var bySize: [Int64: [Candidate]] = [:]
        var seenIdentities = Set<[UInt64]>()
        var seen = 0

        for root in search.roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in skipped.unreadable += 1; return true }) else { continue }
            let rootDevice = FileStamp(root.path)?.device
            for case let item as URL in walker {
                if isCancelled() { return nil }
                guard let st = FileStamp(item.path) else { skipped.unreadable += 1; continue }
                if st.isDirectory {
                    let name = item.lastPathComponent
                    // Another disk mounted inside the folder: its files could appear twice under different identities.
                    if st.device != rootDevice || skippedFolderNames.contains(name) || isEnvironment(item) { walker.skipDescendants() }
                    continue
                }
                guard st.isRegular else { continue }  // links, sockets, devices: never followed or read
                seen += 1
                if seen % 500 == 0 { report(.listing(filesSeen: seen)) }
                guard st.size >= search.minimumSize else { continue }
                if st.dataless { skipped.notDownloaded += 1; continue }
                guard seenIdentities.insert(st.identity).inserted else { continue }  // same file reached twice
                bySize[st.size, default: []].append(Candidate(url: item.standardizedFileURL, size: st.size, identity: st.identity,
                                                              modified: st.modified, changed: st.changed, links: st.links))
            }
        }
        report(.listing(filesSeen: seen))

        let sameSize = bySize.values.filter { $0.count > 1 }
        let total = sameSize.reduce(Int64(0)) { $0 + $1.reduce(0) { $0 + $1.size } }
        var done: Int64 = 0, reported: Int64 = 0
        var groups: [DuplicateGroup] = []
        func advance(_ bytes: Int64) {
            done += bytes
            if done - reported >= 32 << 20 { reported = done; report(.comparing(bytesDone: min(done, total), bytesTotal: total)) }
        }

        for bucket in sameSize {
            if isCancelled() { return nil }
            // Cheap first pass on the start and end of each file; full SHA-256 only where those match.
            var byEnds: [String: [Candidate]] = [:]
            for c in bucket {
                if isCancelled() { return nil }
                guard let key = Hashing.ends(c) else { skipped.unreadable += 1; continue }
                byEnds[key, default: []].append(c)
            }
            for (_, same) in byEnds {
                guard same.count > 1 else { advance(same.reduce(0) { $0 + $1.size }); continue }
                var byDigest: [String: [Candidate]] = [:]
                for c in same {
                    if isCancelled() { return nil }
                    let digest = Hashing.full(c, progress: advance,
                                              isCancelled: isCancelled)
                    guard let digest else {
                        if isCancelled() { return nil }
                        skipped.unreadable += 1; continue
                    }
                    byDigest[digest, default: []].append(c)
                }
                for (digest, copies) in byDigest where copies.count > 1 {
                    let files = copies.map { c in
                        DuplicateFile(url: c.url, size: c.size, identity: c.identity, modified: c.modified, changed: c.changed,
                                      freeable: c.links > 1 ? 0 : (Clones.privateSize(c.url.path) ?? c.size),
                                      viewOnly: search.viewOnlyReason(c.url),
                                      inICloud: (try? c.url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true)
                    }.sorted { $0.url.path < $1.url.path }
                    groups.append(DuplicateGroup(digest: digest, size: copies[0].size, files: files))
                }
            }
            done = min(done, total)
        }
        groups.sort { ($0.wasted, $0.size) > ($1.wasted, $1.size) }
        return (groups, skipped)
    }

    /// A Python or conda environment: its files belong to the environment.
    static func isEnvironment(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appendingPathComponent("pyvenv.cfg").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("conda-meta").path)
    }

}

enum Hashing {
    static let endBytes = 64 * 1024
    static let chunk = 1 << 20

    /// Opens without following links and checks it is still the file that was listed.
    static func open(_ c: DuplicateFinder.Candidate) -> Int32? {
        let fd = Darwin.open(c.url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        var st = stat()
        guard fstat(fd, &st) == 0, [UInt64(UInt32(bitPattern: st.st_dev)), UInt64(st.st_ino)] == c.identity,
              Int64(st.st_size) == c.size else {
            close(fd)
            return nil
        }
        _ = fcntl(fd, F_NOCACHE, 1)  // big model files should not push everything else out of memory
        return fd
    }

    static func ends(_ c: DuplicateFinder.Candidate) -> String? {
        guard let fd = open(c) else { return nil }
        defer { close(fd) }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: endBytes)
        for offset in [Int64(0), max(0, c.size - Int64(endBytes))] {
            let n = pread(fd, &buffer, endBytes, off_t(offset))
            guard n >= 0 else { return nil }
            hasher.update(data: buffer[0..<n])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func full(_ c: DuplicateFinder.Candidate, progress: (Int64) -> Void, isCancelled: () -> Bool) -> String? {
        guard let fd = open(c) else { return nil }
        defer { close(fd) }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: chunk)
        var total: Int64 = 0
        while true {
            if isCancelled() { return nil }
            let n = read(fd, &buffer, chunk)
            guard n >= 0 else { return nil }
            if n == 0 { break }
            hasher.update(data: buffer[0..<n])
            total += Int64(n)
            progress(Int64(n))
        }
        guard total == c.size else { return nil }  // changed while reading
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum Clones {
    /// Bytes of this file not shared with an APFS clone (ATTR_CMNEXT_PRIVATESIZE). Nil where not supported.
    static func privateSize(_ path: String) -> Int64? {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buffer = [UInt8](repeating: 0, count: 64)
        guard getattrlist(path, &list, &buffer, buffer.count, UInt32(FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED)) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> Int64? in
            let returned = raw.load(fromByteOffset: 4, as: attribute_set_t.self)
            guard returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
            return raw.loadUnaligned(fromByteOffset: 4 + MemoryLayout<attribute_set_t>.size, as: Int64.self)
        }
    }
}
