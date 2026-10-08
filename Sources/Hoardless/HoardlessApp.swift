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
                .frame(minWidth: 760, minHeight: 560)
                .task { await model.rescan() }
                .onAppear { NSApplication.shared.activate() }
        }
        .windowResizability(.contentMinSize)
    }
}
