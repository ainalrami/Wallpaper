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
