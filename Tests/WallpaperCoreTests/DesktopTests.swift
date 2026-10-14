import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WallpaperCore

@Suite struct DesktopOptionsTests {
    let red = RGBAColor(red: 1, green: 0, blue: 0)

    @Test func modeMapping() {
        #expect(DesktopOptions(mode: .fill, fillColor: red)
            == DesktopOptions(scaling: .scaleProportionallyUpOrDown, allowClipping: true))
        #expect(DesktopOptions(mode: .fit, fillColor: red)
            == DesktopOptions(scaling: .scaleProportionallyUpOrDown, allowClipping: false, fillColor: red))
        #expect(DesktopOptions(mode: .stretch, fillColor: red)
            == DesktopOptions(scaling: .scaleAxesIndependently, allowClipping: true))
        #expect(DesktopOptions(mode: .center, fillColor: red)
            == DesktopOptions(scaling: .scaleNone, allowClipping: true, fillColor: red))
        #expect(DesktopOptions(mode: .tile, fillColor: red) == DesktopOptions(mode: .fill, fillColor: red))
    }

    @Test(arguments: ScalingMode.allCases)
    func workspaceDictionaryRoundTrip(mode: ScalingMode) {
        let options = DesktopOptions(mode: mode, fillColor: red)
        let decoded = DesktopOptions(workspaceOptions: options.workspaceOptions)
        #expect(decoded.matches(options))
    }

    @Test func matchingIgnoresColorOnlyWhenUnused() {
        let fill = DesktopOptions(mode: .fill, fillColor: .black)
        let fitRed = DesktopOptions(mode: .fit, fillColor: red)
        let fitBlue = DesktopOptions(mode: .fit, fillColor: RGBAColor(red: 0, green: 0, blue: 1))
        #expect(fill.matches(DesktopOptions(scaling: .scaleProportionallyUpOrDown, allowClipping: true, fillColor: red)))
        #expect(!fitRed.matches(fitBlue))
        #expect(!fitRed.matches(fill))
    }
}

@Suite struct TileRendererTests {
    /// A 2x1 image: red on the left, blue on the right.
    private func makeTileImage(in dir: TemporaryDirectory) throws -> URL {
        let context = CGContext(
            data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))

        let url = dir.url.appendingPathComponent("tile.png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func pixels(of url: URL) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &rgba, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (image.width, image.height, rgba)
    }

    @Test func repeatsTileAcrossTargetSize() throws {
        let dir = try TemporaryDirectory()
        let renderer = TileRenderer(cacheDirectory: dir.url.appendingPathComponent("cache"))
        let output = try renderer.tiledImage(for: try makeTileImage(in: dir), pixelWidth: 5, pixelHeight: 3)

        let (width, height, rgba) = try pixels(of: output)
        #expect(width == 5 && height == 3)
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let isRed = column % 2 == 0
                #expect(rgba[offset] == (isRed ? 255 : 0), "red at (\(column), \(row))")
                #expect(rgba[offset + 2] == (isRed ? 0 : 255), "blue at (\(column), \(row))")
            }
        }
    }

    @Test func reusesCachedRender() throws {
        let dir = try TemporaryDirectory()
        let renderer = TileRenderer(cacheDirectory: dir.url.appendingPathComponent("cache"))
        let tile = try makeTileImage(in: dir)
        let first = try renderer.tiledImage(for: tile, pixelWidth: 4, pixelHeight: 4)
        let second = try renderer.tiledImage(for: tile, pixelWidth: 4, pixelHeight: 4)
        let otherSize = try renderer.tiledImage(for: tile, pixelWidth: 8, pixelHeight: 4)
        #expect(first == second)
        #expect(first != otherSize)
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    @Test func unreadableImageThrows() throws {
        let dir = try TemporaryDirectory()
        let bogus = try dir.makeFile("bogus.png", contents: Data("nope".utf8))
        let renderer = TileRenderer(cacheDirectory: dir.url)
        #expect(throws: DesktopError.unreadableImage(bogus.path)) {
            try renderer.tiledImage(for: bogus, pixelWidth: 10, pixelHeight: 10)
        }
    }
}

@Suite @MainActor struct DesktopServiceTests {
    let dir: TemporaryDirectory
    let applier = FakeDesktopApplier()
    let tileOutput: URL
    let service: DesktopService

    init() throws {
        dir = try TemporaryDirectory()
        tileOutput = dir.url.appendingPathComponent("rendered.png")
        service = DesktopService(
            applier: applier,
            tileRenderer: FakeTileRenderer(output: tileOutput),
            displayProvider: FakeDisplayProvider(list: [.main, .external]),
            variantsDirectory: dir.url.appendingPathComponent("variants"))
    }

    @Test func appliesWallpaperWithItsOwnMode() throws {
        let file = try dir.makeFile("a.jpg")
        let red = RGBAColor(red: 1, green: 0, blue: 0)
        try service.apply(Wallpaper(path: file.path, mode: .fit, fillColor: red), to: .main)

        #expect(applier.calls == [.init(displayID: "MAIN", url: file, options: DesktopOptions(mode: .fit, fillColor: red))])
    }

    @Test func tileUsesRenderedImage() throws {
        let file = try dir.makeFile("a.jpg")
        try service.apply(Wallpaper(path: file.path, mode: .tile), to: .main)
        #expect(applier.calls.last?.url == tileOutput)
    }

    @Test func missingFileThrows() {
        #expect(throws: DesktopError.self) {
            try service.apply(Wallpaper(path: dir.url.appendingPathComponent("gone.jpg").path), to: .main)
        }
        #expect(applier.calls.isEmpty)
    }

    @Test func optionChangeOnSameImageUsesVariant() throws {
        let file = try dir.makeFile("a.jpg")
        try service.apply(Wallpaper(path: file.path, mode: .fill), to: .main)
        try service.apply(Wallpaper(path: file.path, mode: .fit), to: .main)

        let variant = try #require(applier.calls.last?.url)
        #expect(variant != file)
        #expect(FileManager.default.contentsEqual(atPath: variant.path, andPath: file.path))

        // Switching back goes to the original file, which now differs from what is shown.
        try service.apply(Wallpaper(path: file.path, mode: .fill), to: .main)
        #expect(applier.calls.last?.url == file)
    }

    @Test func sameOptionsReapplyOriginal() throws {
        let file = try dir.makeFile("a.jpg")
        try service.apply(Wallpaper(path: file.path, mode: .fill), to: .main)
        try service.apply(Wallpaper(path: file.path, mode: .fill), to: .main)
        #expect(applier.calls.map(\.url) == [file, file])
    }

    @Test func sameModeAppliesOneWallpaperEverywhere() throws {
        let a = try dir.makeFile("a.jpg")
        let library = LibraryState(wallpapers: [Wallpaper(path: a.path)])
        var state = RuntimeState()
        state.setWallpaper(a.path, for: nil, mode: .same, displays: [.main, .external])

        let errors = service.applyAssigned(state: state, library: library, mode: .same, displays: [.main, .external])
        #expect(errors.isEmpty)
        #expect(applier.calls.map(\.displayID) == ["MAIN", "EXT"])
        #expect(Set(applier.calls.map(\.url)) == [a])
    }

    @Test func perDisplayAppliesSeparateWallpapers() throws {
        let a = try dir.makeFile("a.jpg")
        let b = try dir.makeFile("b.jpg")
        let library = LibraryState(wallpapers: [Wallpaper(path: a.path), Wallpaper(path: b.path, mode: .center)])
        var state = RuntimeState()
        state.setWallpaper(a.path, for: "MAIN", mode: .perDisplay, displays: [.main, .external])
        state.setWallpaper(b.path, for: "EXT", mode: .perDisplay, displays: [.main, .external])

        service.applyAssigned(state: state, library: library, mode: .perDisplay, displays: [.main, .external])
        #expect(applier.calls.map(\.url) == [a, b])
        #expect(applier.calls[1].options.scaling == .scaleNone)
    }

    @Test func newDisplayGetsSharedWallpaper() throws {
        let a = try dir.makeFile("a.jpg")
        let library = LibraryState(wallpapers: [Wallpaper(path: a.path)])
        var state = RuntimeState()
        state.setWallpaper(a.path, for: nil, mode: .same, displays: [.main])

        service.applyAssigned(state: state, library: library, mode: .perDisplay, displays: [.main, .external])
        #expect(applier.calls.map(\.displayID) == ["MAIN", "EXT"])
    }
}

@Suite struct DisplayAssignmentTests {
    @Test func switchingToPerDisplayKeepsSharedWallpaper() {
        var state = RuntimeState(currentWallpapers: ["*": "a"])
        state.switchDisplayMode(to: .perDisplay, displays: [.main, .external])
        #expect(state.wallpaperID(for: .main, mode: .perDisplay) == "a")
        #expect(state.wallpaperID(for: .external, mode: .perDisplay) == "a")
    }

    @Test func switchingToSameUsesMainDisplay() {
        var state = RuntimeState(currentWallpapers: ["*": "a", "MAIN": "b", "EXT": "c"])
        state.switchDisplayMode(to: .same, displays: [.external, .main])
        #expect(state.wallpaperID(for: .external, mode: .same) == "b")
    }

    @Test func settingForOneDisplayInSameModeSetsAll() {
        var state = RuntimeState()
        state.setWallpaper("a", for: "EXT", mode: .same, displays: [.main, .external])
        #expect(state.currentWallpapers == ["*": "a", "MAIN": "a", "EXT": "a"])
    }

    @Test func forgettingRemovesAssignmentsAndHistory() {
        var state = RuntimeState(currentWallpapers: ["*": "a", "EXT": "b"], cyclingHistory: ["a", "b"])
        state.forgetWallpaper("a")
        #expect(state.currentWallpapers == ["EXT": "b"])
        #expect(state.cyclingHistory == ["b"])
    }
}
