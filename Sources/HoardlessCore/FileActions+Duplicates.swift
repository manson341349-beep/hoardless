import Foundation

/// Trashing duplicate copies. Same promises as the rest of FileActions: only the Trash, every item re-checked on
/// disk right before acting, and here one more: in every group at least one unchanged copy always stays.
extension FileActions {
    public struct DuplicateOutcome: Sendable {
        public var records: [ActionRecord] = []
        public var failures: [(path: String, error: ActionError)] = []
    }

    public static let duplicatesID = "duplicates"

    /// Moves the picked copies (by path) to the Trash. Copies that fail a check are left alone and reported.
    public func trashDuplicates(_ picked: Set<String>, in groups: [DuplicateGroup], search: DuplicateSearch) -> DuplicateOutcome {
        var outcome = DuplicateOutcome()
        for group in groups {
            let chosen = group.files.filter { picked.contains($0.id) }
            guard !chosen.isEmpty else { continue }
            let keepers = group.files.filter { !picked.contains($0.id) }
            for file in chosen {
                // Checked again before every single copy. A keeper must still be the same file and must be a copy that
                // can stay: a copy in an app's data may be cleaned by the app later, so it does not count.
                guard keepers.contains(where: { Self.isUnchanged($0) && $0.canStay && DuplicateFile.stays(search.viewOnlyReason($0.url)) }) else {
                    outcome.failures.append((file.id, .noCopyLeft)); continue
                }
                guard mayTrash(file, search: search) else { outcome.failures.append((file.id, .notAllowed)); continue }
                guard Self.isUnchanged(file) else { outcome.failures.append((file.id, .changedSinceScan)); continue }
                do {
                    let landed = try trasher(file.url)
                    // If something swapped the file in the instant between the checks and the move, put back what was
                    // moved (only if its old spot is still free) and report it instead of keeping it in the Trash.
                    guard Self.identity(landed.path) == file.identity else {
                        if !Self.exists(file.url.path) { try? FileManager.default.moveItem(at: landed, to: file.url) }
                        outcome.failures.append((file.id, .changedSinceScan)); continue
                    }
                    outcome.records.append(ActionRecord(kind: .trashed, ruleID: Self.duplicatesID, locationID: file.id,
                                                        title: file.url.lastPathComponent, original: file.url, now: landed,
                                                        nowIdentity: Self.identity(landed.path), bytes: file.freeable))
                } catch let error as ActionError {
                    outcome.failures.append((file.id, error))
                } catch {
                    outcome.failures.append((file.id, .failed(error.localizedDescription)))
                }
            }
        }
        return outcome
    }

    /// Not view-only (as scanned and as the disk is now), inside a searched folder, inside home, no link in its path.
    func mayTrash(_ file: DuplicateFile, search: DuplicateSearch) -> Bool {
        let url = file.url
        guard file.viewOnly == nil, search.isSearched(url), search.viewOnlyReason(url) == nil,
              url.resolvingSymlinksInPath().path == url.path,
              case .success(let real) = policy.check(url), real.path == url.path else { return false }
        return true
    }

    /// Still the same regular file as when it was compared: same identity, size, modification and status-change time.
    /// The status-change time catches a file rewritten in place with its old modification time put back.
    static func isUnchanged(_ file: DuplicateFile) -> Bool {
        guard let now = FileStamp(file.url.path), now.isRegular else { return false }
        return now.identity == file.identity && now.size == file.size && now.modified == file.modified && now.changed == file.changed
    }
}
