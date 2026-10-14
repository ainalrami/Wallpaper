import Foundation
@testable import WallpaperCore

@MainActor final class FakeDesktopApplier: DesktopApplying {
    struct Call: Equatable {
        var displayID: String
        var url: URL
        var options: DesktopOptions
    }

    var calls: [Call] = []
    var current: [String: (url: URL, options: DesktopOptions)] = [:]

    func currentImage(for displayID: String) -> (url: URL, options: DesktopOptions)? {
        current[displayID]
    }

    func setImage(_ url: URL, options: DesktopOptions, for displayID: String) throws {
        calls.append(Call(displayID: displayID, url: url, options: options))
        current[displayID] = (url, options)
    }
}

struct FakeDisplayProvider: DisplayProviding {
    var list: [Display]
    func displays() -> [Display] { list }
}

struct FakeTileRenderer: TileRendering {
    let output: URL
    func tiledImage(for source: URL, pixelWidth: Int, pixelHeight: Int) throws -> URL { output }
}

extension Display {
    static let main = Display(id: "MAIN", name: "Built-in", pixelWidth: 3024, pixelHeight: 1964, isMain: true)
    static let external = Display(id: "EXT", name: "Studio Display", pixelWidth: 5120, pixelHeight: 2880)
}

final class FakeWatcher: FileSystemWatching, @unchecked Sendable {
    private(set) var paths: [String] = []
    private var onChange: (@Sendable () -> Void)?

    func watch(paths: [String], onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.onChange = onChange
    }

    func stop() {
        paths = []
        onChange = nil
    }
}

/// An `AppController` wired to fakes and a temporary support folder.
@MainActor struct ControllerHarness {
    let support: TemporaryDirectory
    let pictures: TemporaryDirectory
    let applier = FakeDesktopApplier()
    let watcher = FakeWatcher()
    let clock = TestClock()
    var displays: [Display] = [.main]

    init() throws {
        support = try TemporaryDirectory()
        pictures = try TemporaryDirectory()
    }

    var environment: AppEnvironment {
        AppEnvironment(
            paths: AppPaths(supportDirectory: support.url),
            watcher: watcher,
            applier: applier,
            displayProvider: FakeDisplayProvider(list: displays),
            tileRenderer: FakeTileRenderer(output: support.url.appendingPathComponent("tile.png")),
            now: { [clock] in clock.date })
    }

    func makeController() -> AppController {
        AppController(environment: environment)
    }
}

/// A clock tests move forward by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var date: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}
