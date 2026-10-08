import HoardlessCore

/// UI text in Chinese or English, following the user's first preferred language.
struct Strings {
    let chinese: Bool

    private func s(_ zh: String, _ en: String) -> String { chinese ? zh : en }

    var scanning: String { s("正在扫描…", "Scanning…") }
    var heroIdle: String { s("看看你的 Mac\n囤了什么", "See what your Mac is hoarding") }
    var heroScanning: String { s("正在翻找…", "Looking around…") }
    var idleHint: String { s("只读扫描，不会删除任何东西", "Read-only scan. Nothing gets deleted.") }
    func lookingAt(_ app: String) -> String { s("正在查看 \(app)…", "Looking at \(app)…") }
    func doneSummary(actionable: String, protected: String) -> String {
        s("其中 \(actionable) 可以处理 · \(protected) 可能有你的作品，只看不动",
          "\(actionable) you can act on · \(protected) may hold your work, view only")
    }
    var notChecked: String { s("待检查", "Not checked") }
    var tapToCheck: String { s("点开后由你决定是否读取", "Open it to decide") }
    var scan: String { s("扫描", "Scan") }
    var stop: String { s("停止", "Stop") }
    var back: String { s("返回", "Back") }
    var trashButton: String { s("移到废纸篓", "Move to Trash") }
    var moveButton: String { s("挪到…", "Move to…") }
    var chooseFolder: String { s("挪到这里", "Move here") }
    var chooseFolderMessage: String {
        s("选一个文件夹，比如外置硬盘。Hoardless 会在里面建一个 Hoardless 文件夹来放。",
          "Pick a folder, for example on an external drive. Hoardless puts things in a Hoardless folder inside it.")
    }
    func confirmTrashTitle(_ name: String, _ size: String) -> String { s("把\u{201C}\(name)\u{201D}（\(size)）移到废纸篓？", "Move \u{201C}\(name)\u{201D} (\(size)) to the Trash?") }
    func confirmMoveTitle(_ name: String, _ size: String) -> String { s("把\u{201C}\(name)\u{201D}（\(size)）挪走？", "Move \u{201C}\(name)\u{201D} (\(size))?") }
    func confirmTrashBody(path: String, explain: String) -> String {
        s("位置：\(path)\n\n\(explain)\n\n不会永久删除：它会进废纸篓，你随时可以从废纸篓里放回。完成后这里也会出现\u{201C}撤销\u{201D}，在你点\u{201C}知道了\u{201D}、做下一个操作或退出 App 之前有效。",
          "Location: \(path)\n\n\(explain)\n\nNothing is deleted permanently: it goes to the Trash, and you can put it back from there at any time. An Undo button also appears here until you dismiss it, do another action or quit.")
    }
    func confirmMoveBody(path: String, destination: String, explain: String) -> String {
        s("从：\(path)\n到：\(destination)\n\n\(explain)\n\n挪走后，应用会当它已被删除，需要时重新下载。完成后这里会出现\u{201C}撤销\u{201D}，在你点\u{201C}知道了\u{201D}、做下一个操作或退出 App 之前有效；之后要挪回来，请在访达里从上面的位置拖回去。",
          "From: \(path)\nTo: \(destination)\n\n\(explain)\n\nThe app will treat it as deleted and download again when needed. An Undo button appears here until you dismiss it, do another action or quit; after that, drag it back from the location above in Finder.")
    }
    func trashed(_ name: String, _ size: String) -> String { s("已把\u{201C}\(name)\u{201D}（\(size)）移到废纸篓。", "Moved \u{201C}\(name)\u{201D} (\(size)) to the Trash.") }
    func moved(_ name: String, _ size: String, _ to: String) -> String { s("已把\u{201C}\(name)\u{201D}（\(size)）挪到 \(to)。", "Moved \u{201C}\(name)\u{201D} (\(size)) to \(to).") }
    var undo: String { s("撤销", "Undo") }
    var gotIt: String { s("知道了", "OK") }
    var cancel: String { s("取消", "Cancel") }
    var working: String { s("处理中…", "Working…") }
    func actionFailed(_ error: Error) -> String {
        switch error as? ActionError {
        case .notAllowed?: return s("这一项不允许移动或删除。", "This item can't be moved or trashed.")
        case .changedSinceScan?: return s("这个文件夹在扫描后变了，没有动它。请重新扫描后再试。", "This folder changed since the scan, so it was left alone. Rescan and try again.")
        case .badDestination(.notAFolder)?: return s("不能挪到那里：这不是一个已有的文件夹。", "Can't move it there: not an existing folder.")
        case .badDestination(.notAllowedPlace)?: return s("不能挪到那里：只能挪到外置硬盘，或你个人文件夹里的普通文件夹（不能是个人文件夹本身、废纸篓、资源库或缓存文件夹）。", "Can't move it there: pick an external drive or an ordinary folder in your home folder (not the home folder itself, the Trash, Library or a cache folder).")
        case .badDestination(.insideSource)?: return s("不能挪到那里：目标在要挪走的文件夹里面。", "Can't move it there: it is inside the folder being moved.")
        case .badDestination(.linkInside)?: return s("不能挪到那里：目标里的 Hoardless 文件夹是一个链接，指向别处。", "Can't move it there: the Hoardless folder there is a link to somewhere else.")
        case .undoBlocked(.gone(let path))?: return s("没法撤销：它已经不在 \(path) 了。", "Couldn't undo: it is no longer at \(path).")
        case .undoBlocked(.occupied(let path))?: return s("没法撤销：\(path) 已经有新的东西，没有覆盖它。", "Couldn't undo: something new is at \(path), so nothing was overwritten.")
        case .undoBlocked(.unsafeOriginal)?: return s("没法撤销：原来的位置已经不安全了。", "Couldn't undo: the original place is not safe any more.")
        case .undoBlocked(.notSameItem)?: return s("没法撤销：那里的东西已经不是当初挪走的那一个。", "Couldn't undo: the item there is not the one that was moved.")
        case .trashNoLocation?: return s("没有完成：废纸篓没有告诉我们它放到了哪里。", "Didn't finish: the Trash did not report where the item went.")
        case .partialMove(let leftover, let message)?:
            return s("没有挪完（\(message)）。原来的文件夹还在原处；目标位置留下了一份不完整的拷贝：\(leftover)，确认没用后可以自己删掉。",
                     "The move didn't finish (\(message)). The original folder is still in place; an incomplete copy was left at \(leftover). Delete it yourself once you've checked it.")
        case .failed(let why)?: return s("没有完成：\(why)", "Didn't finish: \(why)")
        case nil: return error.localizedDescription
        }
    }
    var fromAppSetting: String { s("应用设置里的位置 · 只显示", "From the app's settings · view only") }
    var fromEnvironment: String { s("环境变量指定的位置 · 只显示", "From an environment variable · view only") }
    func rejected(_ r: RejectedLocation) -> String {
        switch r.kind {
        case .outsideHome?: return s("\(r.path) 不在你的用户目录里（比如外置硬盘），不占这台 Mac 的空间，只列出不测量。",
                                     "\(r.path) is outside your home folder (for example an external drive). It doesn't use this Mac's disk, so it's listed but not measured.")
        case .wholeHome?, .wholeStandardFolder?: return s("\(r.path) 是整个标准文件夹，为了安全不测量。", "\(r.path) is a whole standard folder, so it isn't measured, for safety.")
        case .notHomeRelative?, nil: return "\(r.display) — \(notUsed): \(r.reason)"
        }
    }
    var language: String { s("界面语言", "Language") }
    var languageAuto: String { s("跟随系统", "Auto") }
    var scanFirst: String { s("先回到总览点\u{201C}扫描\u{201D}。", "Go back and press Scan first.") }
    var readOnlyNotice: String { s("扫描只读。移走的东西只进废纸篓或你选的文件夹，不会永久删除。", "Scanning only reads. Anything you remove goes to the Trash or a folder you pick; nothing is deleted permanently.") }
    var rescan: String { s("重新扫描", "Rescan") }
    var loadFailed: String { s("读取规则失败", "Could not load rules") }
    var notFound: String { s("这台 Mac 上没找到", "Not found on this Mac") }
    var notUsed: String { s("未使用", "not used") }
    var checkHere: String { s("检查这里", "Check") }
    var permissionHelp: String {
        s("这个位置属于受保护的文件夹，macOS 可能会弹窗询问是否允许。只有你点了才会读取。",
          "This is a protected folder; macOS may ask for permission. It is only read when you click.")
    }
    var reveal: String { s("在访达中显示", "Show in Finder") }
    var copy: String { s("拷贝", "Copy") }
    var cleanupTitle: String { s("应用自带的清理命令", "The app's own cleanup command") }
    var cleanupWarning: String {
        s("这条命令会永久删除，Hoardless 不会替你运行。运行前请先看清楚它做什么。",
          "This command deletes permanently. Hoardless never runs it for you; read what it does first.")
    }
    var cleanupSource: String { s("官方说明", "Official docs") }
    var safe: String { s("可自动重建", "Safe") }
    var review: String { s("要重新下载", "Review") }
    var commandOnly: String { s("只给命令", "Command only") }
    var protected: String { s("只看", "View only") }

    func category(_ c: Rule.Category) -> String {
        switch c {
        case .aiModels: return s("AI 模型", "AI models")
        case .packageCache: return s("软件包缓存", "Package caches")
        case .videoEditors: return s("剪辑软件", "Video editors")
        case .devTools: return s("开发工具", "Developer tools")
        }
    }

    func state(_ state: LocationState) -> String {
        switch state {
        case .notScanned: return s("等待扫描", "Waiting")
        case .needsPermission: return s("需要你点一下才检查", "Not checked yet")
        case .scanning: return s("扫描中…", "Scanning…")
        case .missing: return s("不存在", "Not present")
        case .measured(let u):
            let size = Bytes.text(u.bytes)
            return u.unreadable > 0 ? s("\(size)（\(u.unreadable) 项无权读取）", "\(size) (\(u.unreadable) unreadable)") : size
        case .failed(let why): return s("出错：\(why)", "Error: \(why)")
        }
    }
}
