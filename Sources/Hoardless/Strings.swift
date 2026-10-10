import HoardlessCore

/// UI text in Chinese or English, following the user's first preferred language.
struct Strings {
    let chinese: Bool

    private func s(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    /// "1 item", "2 items": English needs the singular for one.
    private func n(_ count: Int, _ one: String, _ many: String) -> String { "\(count) \(count == 1 ? one : many)" }

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
        s("位置：\(path)\n\n\(explain)\n\n不会永久删除：它会进废纸篓，清空废纸篓之前都能放回。完成后这里也会出现\u{201C}撤销\u{201D}，在你点\u{201C}知道了\u{201D}、做下一个操作或退出 App 之前有效。",
          "Location: \(path)\n\n\(explain)\n\nNothing is deleted permanently: it goes to the Trash and can be put back until the Trash is emptied. An Undo button also appears here until you dismiss it, do another action or quit.")
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
        case .holdsOtherLocation(let inner)?:
            return s("没有动它：它里面还有另一个位置（\(inner)），那是别的应用或设置在用的。", "Left alone: another location (\(inner)) sits inside it and belongs to another app or setting.")
        case .changedSinceScan?: return s("这个文件夹在扫描后变了，没有动它。请重新扫描后再试。", "This folder changed since the scan, so it was left alone. Rescan and try again.")
        case .badDestination(.notAFolder)?: return s("不能挪到那里：这不是一个已有的文件夹。", "Can't move it there: not an existing folder.")
        case .badDestination(.notAllowedPlace)?: return s("不能挪到那里：只能挪到外置硬盘，或你个人文件夹里的普通文件夹（不能是个人文件夹本身、资源库、废纸篓、隐藏文件夹或缓存文件夹）。", "Can't move it there: pick an external drive or an ordinary folder in your home folder (not the home folder itself, Library, the Trash, a hidden folder or a cache folder).")
        case .badDestination(.insideSource)?: return s("不能挪到那里：目标在要挪走的文件夹里面。", "Can't move it there: it is inside the folder being moved.")
        case .badDestination(.insideAppData)?: return s("不能挪到那里：那是某个应用的数据文件夹，之后清理它时会把挪进去的东西一起带走。", "Can't move it there: it is an app's data folder, and cleaning that later would take what you moved along.")
        case .badDestination(.linkInside)?: return s("不能挪到那里：目标里的 Hoardless 文件夹是一个链接，指向别处。", "Can't move it there: the Hoardless folder there is a link to somewhere else.")
        case .undoBlocked(.gone(let path))?: return s("没法撤销：它已经不在 \(path) 了。", "Couldn't undo: it is no longer at \(path).")
        case .undoBlocked(.occupied(let path))?: return s("没法撤销：\(path) 已经有新的东西，没有覆盖它。", "Couldn't undo: something new is at \(path), so nothing was overwritten.")
        case .undoBlocked(.unsafeOriginal)?: return s("没法撤销：原来的位置已经不安全了。", "Couldn't undo: the original place is not safe any more.")
        case .undoBlocked(.notSameItem)?: return s("没法撤销：那里的东西已经不是当初挪走的那一个。", "Couldn't undo: the item there is not the one that was moved.")
        case .trashNoLocation?: return s("没有完成：废纸篓没有告诉我们它放到了哪里。", "Didn't finish: the Trash did not report where the item went.")
        case .copyIncomplete(let leftover, let message)?:
            return s("没有挪成：复制到那个位置时没有完成\(why(message))。原来的文件夹没有动过。", "Not moved: copying there did not finish\(why(message)). The original folder was not touched.")
                + leftoverNote(leftover)
        case .changedWhileCopying(let leftover)?:
            return s("没有挪成：复制的过程中，这个文件夹里有东西在变（相关软件可能还开着）。原来的文件夹没有动过；先退出那个软件再试。",
                     "Not moved: something in this folder changed while it was being copied (the app may still be running). The original folder was not touched; quit that app and try again.")
                + leftoverNote(leftover)
        case .originalChanged(let copy)?:
            return s("没有挪成：复制好之后，原来的文件夹被换掉或不见了，所以没有把它移到废纸篓。复制好的完整一份留在：\(copy)",
                     "Not moved: after the copy was made, the original folder was replaced or disappeared, so it was not sent to the Trash. The complete copy was kept at \(copy)")
        case .originalKept(let copy, let message)?:
            return s("没有挪成：已经复制好了，但原来的文件夹没能移到废纸篓\(why(message))，所以这次挪动撤回了，原文件夹原样留着。",
                     "Not moved: the copy was made, but the original folder could not go to the Trash\(why(message)), so the move was undone and the original is unchanged.")
                + (copy.map { s("复制好的那份没能移到废纸篓，现在两边各有一份完整的；另一份在：\($0)", " The copy could not go to the Trash either, so there are now two full copies; the other one is at \($0)") } ?? "")
        case .noCopyLeft?: return s("没有动它：这一组里没有别的副本还原样留着，删了就一份都不剩。", "Left alone: no other copy in this group is still unchanged, so this would be the last one.")
        case .failed(let why)?: return s("没有完成：\(why)", "Didn't finish: \(why)")
        case nil: return error.localizedDescription
        }
    }
    private func why(_ message: String) -> String { message.isEmpty ? "" : s("（\(message)）", " (\(message))") }
    private func leftoverNote(_ leftover: String?) -> String {
        leftover.map { s("那份没复制完的拷贝没能移到废纸篓，还留在：\($0)，可以放心删掉。", " The unfinished copy could not go to the Trash and is still at \($0); it is safe to delete.") } ?? ""
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
    var languageNote: String { s("菜单栏会在下次打开 App 时跟着变", "The menu bar follows from the next launch") }
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

    // MARK: sidebar, overview, category pages (2026-10-09 redesign)

    var overview: String { s("总览", "Overview") }
    var sectionSpace: String { s("空间", "Space") }
    var sectionTools: String { s("工具", "Tools") }
    var settings: String { s("设置", "Settings") }
    var goBack: String { s("后退", "Back") }
    var goForward: String { s("前进", "Forward") }
    var scanDone: String { s("扫描完成", "Scan complete") }
    var idleTitle: String { s("看看你的 Mac 囤了什么", "See what your Mac is hoarding") }
    func doneParagraph(actionable: String, protected: String) -> String {
        s("AI 工具和剪辑软件在这台 Mac 上囤了这么多。其中 \(actionable) 可以处理，\(protected) 可能有你的作品，只看不动。",
          "That is what AI tools and video editors keep on this Mac. \(actionable) you can act on; \(protected) may hold your work and is view only.")
    }
    func reviewAction(_ size: String) -> String { s("查看可以处理的 \(size)", "Review the \(size) you can act on") }
    func canAct(_ size: String) -> String { s("可处理 \(size)", "\(size) can go") }
    func commandOnlyAmount(_ size: String) -> String { s("只给命令 \(size)", "\(size) by command") }
    var viewOnlyAll: String { s("只看", "View only") }
    var dupCardAction: String { s("去查找", "Find") }
    var dupCardHint: String { s("在你选的文件夹里", "In folders you pick") }
    func categoryAbout(_ c: Rule.Category) -> String {
        switch c {
        case .videoEditors: return s("剪辑软件的缓存、下载的素材和草稿。能自己重建的缓存可以放心清理；草稿和下载的素材只显示大小。",
                                     "Video editors' caches, downloaded material and drafts. Caches they rebuild can go; drafts and downloaded material are view only.")
        case .aiModels: return s("Hugging Face、PyTorch、Ollama 等下载的模型和缓存。需要时会重新下载；你自己训练或改过的模型只显示大小。",
                                 "Models and caches downloaded by Hugging Face, PyTorch, Ollama and others. They download again when needed; models you made are view only.")
        case .packageCache: return s("pip、uv、npm、pnpm、Homebrew 等下载过的安装包。删掉后，下次安装时会重新下载。",
                                     "Packages downloaded by pip, uv, npm, pnpm, Homebrew and others. They download again the next time you install.")
        case .devTools: return s("Docker、Playwright 等开发工具的数据。可能有你的项目数据或登录记录的，只显示大小。",
                                 "Data of developer tools such as Docker and Playwright. Anything that may hold project data or logins is view only.")
        }
    }
    func locationsCount(_ n: Int) -> String { s("\(n) 个位置", self.n(n, "location", "locations")) }
    var permissionRow: String { s("在受保护的文件夹里，macOS 会先问你", "In a protected folder; macOS asks you first") }
    var allowAndCheck: String { s("允许并检查", "Allow and check") }
    func selectedSummary(_ n: Int, _ size: String) -> String { s("已选 \(n) 项 · \(size)", "\(n) selected · \(size)") }
    var pickHint: String { s("勾选要处理的项目。没有勾选框的只看不动。", "Tick what to act on. Items without a box are view only.") }
    var undoable: String { s("确认前会列出全部路径，可撤销", "Every path is listed before anything moves; can be undone") }
    func undoFailed(_ original: String, now: String, _ why: String) -> String {
        s("\(original) 没能放回（\(why)）。它现在在：\(now)", "\(original) was not put back (\(why)). It is now at: \(now)")
    }
    func batchTrashTitle(_ n: Int, _ places: Int, _ size: String) -> String {
        s("把 \(n) 项（\(places) 个位置，\(size)）移到废纸篓？", "Move \(self.n(n, "item", "items")) (\(self.n(places, "place", "places")), \(size)) to the Trash?")
    }
    func batchMoveTitle(_ n: Int, _ places: Int, _ size: String) -> String {
        s("把 \(n) 项（\(places) 个位置，\(size)）挪走？", "Move \(self.n(n, "item", "items")) (\(self.n(places, "place", "places")), \(size))?")
    }
    var batchTrashNote: String {
        s("不会永久删除：它们会进废纸篓，清空废纸篓之前都能放回。完成后这里会出现\u{201C}撤销\u{201D}，在你点\u{201C}知道了\u{201D}、做下一个操作或退出 App 之前有效。",
          "Nothing is deleted permanently: they go to the Trash and can be put back until it is emptied. An Undo button appears here until you dismiss it, act again or quit.")
    }
    var batchMoveNote: String {
        s("挪之前请先退出相关的软件。挪走后，应用会当它们已被删除，需要时重新下载。挪到另一个硬盘时，会先完整复制、核对一遍，再把原来的文件夹移到废纸篓（不会直接删除），清空废纸篓后才会腾出这台 Mac 的空间。完成后这里会出现\u{201C}撤销\u{201D}，在你点\u{201C}知道了\u{201D}、做下一个操作或退出 App 之前有效。",
          "Quit the apps that use them first. The apps will treat them as deleted and download again when needed. On another drive, everything is copied and checked first, then the originals go to the Trash (never deleted); this Mac's space comes back once the Trash is emptied. An Undo button appears here until you dismiss it, act again or quit.")
    }
    func moveToICloudWarning(_ size: String) -> String {
        s("这个文件夹会同步到 iCloud：挪进去的 \(size) 会上传到 iCloud、占用 iCloud 空间，也会出现在你的其他设备上。建议改挪到外置硬盘。",
          "This folder syncs to iCloud: the \(size) moved here will upload to iCloud, use iCloud storage and appear on your other devices. An external drive is a better choice.")
    }
    var colon: String { s("：", ": ") }
    var quitWhileWorkingTitle: String { s("Hoardless 还在挪动或放回文件", "Hoardless is still moving or putting back files") }
    var quitWhileWorkingBody: String {
        s("现在退出，可能会在目标位置留下一份没复制完的拷贝（原来的文件不会丢）。建议等它做完再退出。",
          "Quitting now may leave an unfinished copy at the destination (the originals are not lost). It is better to wait until it finishes.")
    }
    var keepWorking: String { s("等它做完", "Wait") }
    var quitAnyway: String { s("仍然退出", "Quit Anyway") }
    var whatTheyAre: String { s("它们是什么", "What they are") }
    func batchTrashed(_ n: Int, _ size: String) -> String { s("已把 \(n) 项（\(size)）移到废纸篓。", "Moved \(self.n(n, "item", "items")) (\(size)) to the Trash.") }
    func batchMoved(_ n: Int, _ size: String) -> String { s("已把 \(n) 项（\(size)）挪走。", "Moved \(self.n(n, "item", "items")) (\(size)).") }

    // MARK: settings window

    var general: String { s("通用", "General") }
    var searchTab: String { s("查找", "Finding") }
    var about: String { s("关于", "About") }
    var autoScan: String { s("打开 App 时自动扫描", "Scan when the app opens") }
    var autoScanNote: String { s("只读，不会动任何文件", "Read-only; no file is changed") }
    var askFirst: String { s("移走前一定先问我", "Always ask before removing") }
    var askFirstNote: String { s("安全规则，不能关闭：每次挪走或丢进废纸篓都会先列出路径和大小", "A safety rule that can't be turned off: every move or trash lists the paths and sizes first") }
    var dupMinimum: String { s("重复文件的最小大小", "Smallest duplicate to look for") }
    var dupMinimumNote: String { s("更小的文件腾不出多少空间，还会让列表很长", "Smaller files free little space and make the list long") }
    var version: String { s("版本", "Version") }
    var licenseNote: String { s("免费开源（GPL-3.0）。不用注册，没有广告，不收集任何数据。图片版权保留。", "Free and open source (GPL-3.0). No account, no ads, no data collected. Artwork all rights reserved.") }
    var sourceCode: String { s("在 GitHub 上查看源代码", "Source code on GitHub") }

    // MARK: duplicates

    var dupTitle: String { s("重复文件", "Duplicates") }
    var dupTileHint: String { s("在你选的文件夹里找一模一样的文件", "Find identical files in folders you pick") }
    func dupTileFound(_ groups: Int) -> String { s("\(groups) 组重复", n(groups, "duplicate set", "duplicate sets")) }
    var dupSearchIn: String { s("在这些文件夹里找", "Look in these folders") }
    var dupAdd: String { s("添加文件夹…", "Add Folder…") }
    var dupAddPrompt: String { s("添加", "Add") }
    var dupRemove: String { s("移除", "Remove") }
    var dupSuggested: String { s("常用", "Suggested") }
    func dupRefused(_ path: String, _ why: DuplicateSearch.RootProblem) -> String {
        switch why {
        case .outsideHome: return s("\(path) 不在你的个人文件夹里，不能查找。", "\(path) is outside your home folder.")
        case .wholeHome: return s("不能直接查整个个人文件夹，请选里面的文件夹。", "Pick folders inside your home folder, not the whole home folder.")
        case .library: return s("\(path) 在资源库（Library）里，那是应用自己的数据，不能查找。", "\(path) is in Library, which holds apps' own data.")
        case .trash: return s("不能查找废纸篓。", "The Trash can't be searched.")
        case .notAFolder: return s("\(path) 不是文件夹，或者已经不在了。", "\(path) is not a folder, or is gone.")
        case .insidePackage: return s("\(path) 是应用或图库这类\u{201C}包\u{201D}（或在它里面），里面的文件归应用管，不能查找。", "\(path) is, or is inside, an app or library package; its files belong to the app.")
        case .otherVolume: return s("\(path) 在另一个磁盘上，这里只查这台 Mac 的个人文件夹所在的磁盘。", "\(path) is on another disk; only the disk your home folder is on is searched.")
        }
    }
    func dupHowItWorks(_ minimum: String) -> String {
        s("只读查找：只比较文件内容，不改动任何东西。只找 \(minimum) 以上的文件（可在设置里改）；隐藏文件夹、应用包内部、Python 环境和 node_modules 不进去看。下载、桌面、文稿等文件夹第一次读取时，macOS 可能会弹窗询问。",
          "Read-only: it only compares file contents and changes nothing. Files under \(minimum) are ignored (change it in Settings); hidden folders, app packages, Python environments and node_modules are not looked inside. macOS may ask before Downloads, Desktop or Documents is read the first time.")
    }
    var dupRulesMissing: String {
        s("没有开始查找：规则文件没能读取，就认不出哪些文件夹是应用的数据。为了安全，这次不查找。请重新安装 Hoardless。",
          "Not searching: the rule files could not be read, so apps' own folders can't be recognised. To be safe, nothing is searched. Please reinstall Hoardless.")
    }
    var dupStart: String { s("开始查找", "Find Duplicates") }
    func dupListing(_ n: Int) -> String { s("正在查看文件… 已看 \(n) 个", "Looking through files… \(n) so far") }
    func dupComparing(_ done: Int64, _ total: Int64) -> String {
        s("正在比对内容 \(Bytes.text(done)) / \(Bytes.text(total))", "Comparing contents \(Bytes.text(done)) of \(Bytes.text(total))")
    }
    func dupSummary(_ groups: Int, _ bytes: Int64) -> String {
        s("找到 \(groups) 组重复，最多可腾出 \(Bytes.text(bytes))", "\(n(groups, "set", "sets")) of duplicates, up to \(Bytes.text(bytes)) to free")
    }
    var dupNone: String { s("没有找到可以处理的重复文件。", "No duplicates you can act on.") }
    var dupNewSearch: String { s("重新查找", "New Search") }
    var dupKeepOneAll: String { s("每组只留一份", "Keep One of Each") }
    var dupClear: String { s("全部不选", "Select None") }
    func dupShowViewOnly(_ n: Int) -> String { s("也显示只能查看的 \(n) 组（应用数据、代码仓库等）", "Also show \(self.n(n, "view-only set", "view-only sets")) (app data, code repositories…)") }
    func dupCopies(_ size: Int64, _ count: Int) -> String { s("\(Bytes.text(size)) × \(count) 份", "\(Bytes.text(size)) × \(count)") }
    func dupGroupWasted(_ bytes: Int64) -> String { s("可腾出 \(Bytes.text(bytes))", "\(Bytes.text(bytes)) to free") }
    var dupKeepOne: String { s("只留一份", "Keep One") }
    func dupViewOnlyTag(_ reason: DuplicateFile.ViewOnly) -> String {
        switch reason {
        case .appFolder: return s("应用数据 · 只看", "App data · view only")
        case .codeRepository: return s("代码仓库 · 只看", "Code repository · view only")
        case .toolFolder: return s("开发环境 · 只看", "Environment · view only")
        case .hardLinked: return s("硬链接 · 只看", "Hard link · view only")
        }
    }
    func dupViewOnlyHelp(_ reason: DuplicateFile.ViewOnly) -> String {
        switch reason {
        case .appFolder(let path): return s("在 \(path) 里，是应用自己的数据。删掉可能让应用出问题，所以 Hoardless 不动它。", "Inside \(path), an app's own data. Removing it could break the app, so Hoardless leaves it alone.")
        case .codeRepository: return s("在代码仓库里，删掉会改动这个项目。", "Inside a code repository; removing it would change the project.")
        case .toolFolder: return s("在 Python 环境或软件包文件夹里，删掉会让它不完整。", "Inside a Python environment or package folder; removing it would break it.")
        case .hardLinked: return s("这个文件在别处还有一个硬链接名字，删掉这一个也腾不出空间。", "This file has another hard-linked name; trashing this one frees nothing.")
        }
    }
    var dupLastCopy: String { s("每组至少要留一份", "At least one copy must stay") }
    func dupShares(_ bytes: Int64) -> String {
        bytes == 0 ? s("和另一份共用磁盘空间，删掉它腾不出空间", "Shares its space with another copy; trashing it frees nothing")
                   : s("和另一份共用空间，删掉只腾出 \(Bytes.text(bytes))", "Shares space with another copy; frees \(Bytes.text(bytes))")
    }
    func dupSelected(_ n: Int, _ bytes: Int64) -> String { s("已选 \(n) 个文件 · \(Bytes.text(bytes))", "\(n) selected · \(Bytes.text(bytes))") }
    var dupNoneSelected: String { s("勾选要移走的副本，每组至少留一份。", "Tick the copies to remove; one of each always stays.") }
    func dupConfirmTitle(_ n: Int, _ bytes: Int64) -> String { s("把 \(n) 个文件（\(Bytes.text(bytes))）移到废纸篓？", "Move \(self.n(n, "file", "files")) (\(Bytes.text(bytes))) to the Trash?") }
    var dupConfirmKeep: String { s("每组都会至少留下一份原样的文件。要移到废纸篓的是：", "At least one unchanged copy of each file stays. These go to the Trash:") }
    var dupConfirmTrashNote: String {
        s("不会永久删除：它们会进废纸篓，清空废纸篓之前都能放回；空间要等清空废纸篓后才真正腾出来。完成后这里也会出现\u{201C}撤销\u{201D}，在你点\u{201C}知道了\u{201D}、再次移走或重新查找之前有效。",
          "Nothing is deleted permanently: they go to the Trash and can be put back until it is emptied; the space comes back once it is. An Undo button also appears here until you dismiss it, remove more or start a new search.")
    }
    func dupICloudWarning(_ n: Int) -> String {
        s("其中 \(n) 个在 iCloud 云盘里（比如同步的桌面或文稿）：移到废纸篓后，你其他设备上的这份也会一起移走。",
          (n == 1 ? "1 of them is" : "\(n) of them are") + " in iCloud Drive (for example a synced Desktop or Documents): your other devices lose this copy too.")
    }
    func dupTrashed(_ n: Int, _ bytes: Int64) -> String { s("已把 \(n) 个文件（\(Bytes.text(bytes))）移到废纸篓。", "Moved \(self.n(n, "file", "files")) (\(Bytes.text(bytes))) to the Trash.") }
    func dupSkipped(_ k: DuplicateFinder.Skipped) -> String? {
        var parts: [String] = []
        if k.notDownloaded > 0 { parts.append(s("\(k.notDownloaded) 个还没下载到这台 Mac 的 iCloud 文件", n(k.notDownloaded, "iCloud file", "iCloud files") + " not downloaded to this Mac")) }
        if k.unreadable > 0 { parts.append(s("\(k.unreadable) 个无法读取的项目", n(k.unreadable, "item", "items") + " that could not be read")) }
        guard !parts.isEmpty else { return nil }
        return s("跳过了 ", "Skipped ") + parts.joined(separator: s("、", ", ")) + s("。", ".")
    }

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
