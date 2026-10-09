import AppKit
import SwiftUI

@main
struct HoardlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var duplicates = DuplicateModel()

    init() {
        // Needed when launched as a bare executable (swift run); harmless inside a .app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Hoardless", id: AppDelegate.mainWindowID) {
            ContentView()
                .environmentObject(model)
                .environmentObject(duplicates)
                .frame(minWidth: 1040, minHeight: 700)
                .onAppear {
                    NSApplication.shared.activate()
                    model.appeared()
                }
                .modifier(RememberOpenWindow())
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 780)
        // One window: the scan, the ticks and the confirmation sheet belong to it.
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(duplicates)
        }
    }
}

/// Closing the window leaves the app running (the scan, and the Undo for the last move, are kept). SwiftUI does not
/// bring the window back by itself when the Dock icon is clicked then, so this opens it again.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let mainWindowID = "main"
    /// SwiftUI's own "open window" action, taken from the window when it first appears.
    @MainActor static var openWindow: OpenWindowAction?

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let open = Self.openWindow else { return true }
        open(id: Self.mainWindowID)
        return false
    }
}

private struct RememberOpenWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { AppDelegate.openWindow = openWindow }
    }
}
