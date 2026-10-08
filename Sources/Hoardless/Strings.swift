import HoardlessCore

/// UI text in Chinese or English, following the user's first preferred language.
struct Strings {
    let chinese: Bool

    private func s(_ zh: String, _ en: String) -> String { chinese ? zh : en }

    var scanning: String { s("正在扫描…", "Scanning…") }
    func found(_ size: String) -> String { s("找到 \(size)", "Found \(size)") }
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
            let size = ContentView.size(u.bytes)
            return u.unreadable > 0 ? s("\(size)（\(u.unreadable) 项无权读取）", "\(size) (\(u.unreadable) unreadable)") : size
        case .failed(let why): return s("出错：\(why)", "Error: \(why)")
        }
    }
}
