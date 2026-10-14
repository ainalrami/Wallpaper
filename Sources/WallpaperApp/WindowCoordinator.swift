import AppKit
import SwiftUI
import WallpaperCore

/// Opens the library and settings windows. The app shows a Dock icon only while one is open.
@MainActor @Observable final class WindowCoordinator: NSObject, NSWindowDelegate {
    @ObservationIgnored private let controller: AppController
    @ObservationIgnored private var windows: [String: NSWindow] = [:]

    init(controller: AppController) {
        self.controller = controller
    }

    func showLibrary() {
        show(id: "library", title: "Wallpaper Library", size: NSSize(width: 1040, height: 680), resizable: true) {
            LibraryView()
        }
    }

    func showSettings() {
        show(id: "settings", title: "Settings", size: NSSize(width: 560, height: 420), resizable: false) {
            SettingsView()
        }
    }

    private func show<Content: View>(
        id: String, title: String, size: NSSize, resizable: Bool, @ViewBuilder content: () -> Content
    ) {
        let window = windows[id] ?? makeWindow(id: id, title: title, size: size, resizable: resizable, content: content())
        windows[id] = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow<Content: View>(
        id: String, title: String, size: NSSize, resizable: Bool, content: Content
    ) -> NSWindow {
        let hosting = NSHostingController(rootView: content.environment(controller).environment(self))
        if !resizable {
            hosting.sizingOptions = .preferredContentSize
        }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable {
            style.insert(.resizable)
            style.insert(.fullSizeContentView)
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(size)
        window.setFrameAutosaveName("WallpaperManager.\(id)")
        if !window.setFrameUsingName(window.frameAutosaveName) {
            window.center()
        }
        return window
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        // Back to a menu bar-only app once the last window closes.
        if !windows.values.contains(where: { $0 !== closing && $0.isVisible }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
