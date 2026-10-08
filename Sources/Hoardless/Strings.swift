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
    var language: String { s("界面语言", "Language") }
    var languageAuto: String { s("跟随系统", "Auto") }
    var scanFirst: String { s("先回到总览点\u{201C}扫描\u{201D}。", "Go back and press Scan first.") }
    var readOnlyNotice: String { s("只读版本：只查看占用，不会删除或移动任何文件。", "Read-only version: it only looks. Nothing is deleted or moved.") }
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
