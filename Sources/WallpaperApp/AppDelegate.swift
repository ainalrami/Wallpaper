import AppKit
import WallpaperCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: AppController
    let windows: WindowCoordinator
    private var observers: [NSObjectProtocol] = []

    override init() {
        controller = AppController(environment: .live())
        windows = WindowCoordinator(controller: controller)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.onLibraryEmpty = { [weak self] in self?.windows.showLibrary() }
        if controller.needsOnboarding {
            windows.showLibrary()
        }
        observeSystemEvents()
        Task { await controller.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showLibrary()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func observeSystemEvents() {
        let reapply: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.controller.reapplyCurrent() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reapply))
        // macOS only changes the wallpaper of the active Space, so apply it when Spaces change.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: reapply))
        // Timers don't fire during sleep, so check for a due change on wake.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.controller.rotationTick() }
        })
    }
}
