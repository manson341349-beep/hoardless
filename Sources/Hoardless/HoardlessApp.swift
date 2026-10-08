import AppKit
import SwiftUI

@main
struct HoardlessApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Needed when launched as a bare executable (swift run); harmless inside a .app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Hoardless") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 680)
                .onAppear { NSApplication.shared.activate() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 720)
    }
}
