import Foundation
import Testing
@testable import WallpaperCore

@Suite @MainActor struct AppControllerTests {
    @Test func emptyLibraryNeedsOnboarding() async throws {
        let harness = try ControllerHarness()
        let controller = harness.makeController()
        #expect(controller.needsOnboarding)

        var emptyCallbacks = 0
        controller.onLibraryEmpty = { emptyCallbacks += 1 }
        await controller.start()
        #expect(controller.needsOnboarding)
        #expect(emptyCallbacks == 1)
    }

    @Test func addingFolderPopulatesLibraryAndWatchesIt() async throws {
        let harness = try ControllerHarness()
        try harness.pictures.makeFile("a.jpg")
        try harness.pictures.makeFile("b.png")
        let controller = harness.makeController()
        await controller.start()

        await controller.addSources([harness.pictures.url])
        #expect(controller.library.wallpapers.count == 2)
        #expect(!controller.needsOnboarding)
        #expect(harness.watcher.paths == [harness.pictures.url.path])
    }

    @Test func deletingAllImagesShowsOnboardingAgain() async throws {
        let harness = try ControllerHarness()
        let file = try harness.pictures.makeFile("a.jpg")
        let controller = harness.makeController()
        await controller.start()
        await controller.addSources([harness.pictures.url])

        var emptied = false
        controller.onLibraryEmpty = { emptied = true }
        try FileManager.default.removeItem(at: file)
        await controller.rescan()

        #expect(controller.library.wallpapers.isEmpty)
        #expect(controller.needsOnboarding)
        #expect(emptied)
    }

    @Test func newFilesUseDefaultMode() async throws {
        let harness = try ControllerHarness()
        try harness.pictures.makeFile("a.jpg")
        let controller = harness.makeController()
        controller.settings.defaultMode = .fit
        controller.settings.defaultFillColor = .white
        await controller.addSources([harness.pictures.url])

        #expect(controller.library.wallpapers.first?.mode == .fit)
        #expect(controller.library.wallpapers.first?.fillColor == .white)
    }

    @Test func perWallpaperModeIsPersisted() async throws {
        let harness = try ControllerHarness()
        let file = try harness.pictures.makeFile("a.jpg")
        let controller = harness.makeController()
        await controller.addSources([harness.pictures.url])
        let red = RGBAColor(red: 1, green: 0, blue: 0)
        controller.updateWallpaper(id: file.path) {
            $0.mode = .fit
            $0.fillColor = red
        }

        let reloaded = harness.makeController()
        await reloaded.start()
        #expect(reloaded.library.wallpaper(id: file.path)?.mode == .fit)
        #expect(reloaded.library.wallpaper(id: file.path)?.fillColor == red)
    }

    @Test func settingWallpaperAppliesItsOwnMode() async throws {
        let harness = try ControllerHarness()
        let a = try harness.pictures.makeFile("a.jpg")
        let b = try harness.pictures.makeFile("b.jpg")
        let controller = harness.makeController()
        await controller.addSources([harness.pictures.url])
        controller.updateWallpaper(id: a.path) { $0.mode = .fit }
        controller.updateWallpaper(id: b.path) { $0.mode = .stretch }

        controller.setWallpaper(id: a.path)
        #expect(harness.applier.calls.last?.options.scaling == .scaleProportionallyUpOrDown)
        #expect(harness.applier.calls.last?.options.allowClipping == false)
        controller.setWallpaper(id: b.path)
        #expect(harness.applier.calls.last?.options.scaling == .scaleAxesIndependently)
        controller.setWallpaper(id: a.path)
        #expect(harness.applier.calls.last?.options.allowClipping == false)
    }

    @Test func changingModeOfShownWallpaperReappliesIt() async throws {
        let harness = try ControllerHarness()
        let a = try harness.pictures.makeFile("a.jpg")
        let controller = harness.makeController()
        await controller.addSources([harness.pictures.url])
        controller.setWallpaper(id: a.path)
        let callsBefore = harness.applier.calls.count

        controller.updateWallpaper(id: a.path) { $0.mode = .center }
        #expect(harness.applier.calls.count == callsBefore + 1)
        #expect(harness.applier.calls.last?.options.scaling == .scaleNone)
    }

    @Test func changingModeOfOtherWallpaperDoesNotTouchDesktop() async throws {
        let harness = try ControllerHarness()
        let a = try harness.pictures.makeFile("a.jpg")
        let b = try harness.pictures.makeFile("b.jpg")
        let controller = harness.makeController()
        await controller.addSources([harness.pictures.url])
        controller.setWallpaper(id: a.path)
        let callsBefore = harness.applier.calls.count

        controller.updateWallpaper(id: b.path) { $0.mode = .tile }
        #expect(harness.applier.calls.count == callsBefore)
    }

    @Test func perDisplayModeSetsOnlyChosenDisplay() async throws {
        var harness = try ControllerHarness()
        harness.displays = [.main, .external]
        let a = try harness.pictures.makeFile("a.jpg")
        let b = try harness.pictures.makeFile("b.jpg")
        let controller = harness.makeController()
        await controller.start()
        await controller.addSources([harness.pictures.url])
        controller.setWallpaper(id: a.path)
        controller.settings.displayMode = .perDisplay

        controller.setWallpaper(id: b.path, displayID: Display.external.id)
        #expect(harness.applier.calls.last?.displayID == Display.external.id)
        #expect(controller.currentWallpaper(on: .main)?.path == a.path)
        #expect(controller.currentWallpaper(on: .external)?.path == b.path)
    }

    @Test func reapplySkipsDisplaysAlreadyShowingWallpaper() async throws {
        let harness = try ControllerHarness()
        let a = try harness.pictures.makeFile("a.jpg")
        let controller = harness.makeController()
        await controller.addSources([harness.pictures.url])
        controller.setWallpaper(id: a.path)
        let callsBefore = harness.applier.calls.count

        controller.reapplyCurrent()
        #expect(harness.applier.calls.count == callsBefore)

        // Another Space or app changed the desktop: re-apply.
        harness.applier.current[Display.main.id] = (URL(fileURLWithPath: "/other.jpg"), DesktopOptions(mode: .fill, fillColor: .black))
        controller.reapplyCurrent()
        #expect(harness.applier.calls.count == callsBefore + 1)
    }

    @Test func removingSourceRemovesItsWallpapers() async throws {
        let harness = try ControllerHarness()
        try harness.pictures.makeFile("a.jpg")
        let controller = harness.makeController()
        await controller.addSources([harness.pictures.url])
        let source = try #require(controller.library.sources.first)

        await controller.removeSource(id: source.id)
        #expect(controller.library.wallpapers.isEmpty)
        #expect(controller.library.sources.isEmpty)
    }

    @Test func excludingFromCyclingIsSaved() async throws {
        let harness = try ControllerHarness()
        let a = try harness.pictures.makeFile("a.jpg")
        let controller = harness.makeController()
        await controller.addSources([harness.pictures.url])
        controller.setIncludedInCycling(false, ids: [a.path])

        let reloaded = harness.makeController()
        #expect(reloaded.library.wallpaper(id: a.path)?.includedInCycling == false)
    }
}

@Suite struct WallpaperLayoutTests {
    let canvas = CGRect(x: 0, y: 0, width: 160, height: 90)
    let display = CGSize(width: 1600, height: 900)

    @Test func fillCoversCanvas() {
        let rects = WallpaperLayout.imageRects(
            mode: .fill, imageSize: CGSize(width: 100, height: 100), canvas: canvas, displayPixelSize: display)
        #expect(rects == [CGRect(x: 0, y: -35, width: 160, height: 160)])
    }

    @Test func fitLeavesBars() {
        let rects = WallpaperLayout.imageRects(
            mode: .fit, imageSize: CGSize(width: 100, height: 100), canvas: canvas, displayPixelSize: display)
        #expect(rects == [CGRect(x: 35, y: 0, width: 90, height: 90)])
    }

    @Test func stretchMatchesCanvas() {
        let rects = WallpaperLayout.imageRects(
            mode: .stretch, imageSize: CGSize(width: 10, height: 500), canvas: canvas, displayPixelSize: display)
        #expect(rects == [canvas])
    }

    @Test func centerKeepsActualSize() {
        let rects = WallpaperLayout.imageRects(
            mode: .center, imageSize: CGSize(width: 800, height: 450), canvas: canvas, displayPixelSize: display)
        #expect(rects == [CGRect(x: 40, y: 22.5, width: 80, height: 45)])
    }

    @Test func tileRepeatsFromTopLeft() {
        let rects = WallpaperLayout.imageRects(
            mode: .tile, imageSize: CGSize(width: 600, height: 400), canvas: canvas, displayPixelSize: display)
        // 60x40 tiles: 3 columns x 3 rows cover 160x90.
        #expect(rects.count == 9)
        #expect(rects.first == CGRect(x: 0, y: 0, width: 60, height: 40))
    }
}
