import SwiftUI
import WallpaperCore

@main
struct WallpaperApp: App {
    var body: some Scene {
        MenuBarExtra(WallpaperCore.appName, systemImage: "photo.on.rectangle") {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
