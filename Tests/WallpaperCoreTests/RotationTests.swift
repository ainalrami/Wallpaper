import Foundation
import Testing
@testable import WallpaperCore

@Suite struct WallpaperPickerTests {
    let wallpapers = (1...5).map { Wallpaper(path: "/w/\($0).jpg") }

    @Test func randomShowsEveryWallpaperBeforeRepeating() {
        var generator = SystemRandomNumberGenerator()
        var history: [String] = []
        var current: String?
        var shown: [String] = []
        for _ in wallpapers {
            let pick = WallpaperPicker.next(
                from: wallpapers, order: .random, current: current, history: history, using: &generator)!
            history = pick.history
            current = pick.wallpaperID
            shown.append(pick.wallpaperID)
        }
        #expect(Set(shown).count == wallpapers.count)

        // A new cycle starts, but never with the wallpaper shown right now.
        let next = WallpaperPicker.next(from: wallpapers, order: .random, current: current, history: history, using: &generator)!
        #expect(next.wallpaperID != current)
        #expect(next.history == [next.wallpaperID])
    }

    @Test func sequentialAdvancesAndWraps() {
        var generator = SystemRandomNumberGenerator()
        let first = WallpaperPicker.next(from: wallpapers, order: .sequential, current: nil, history: [], using: &generator)
        let afterThird = WallpaperPicker.next(from: wallpapers, order: .sequential, current: "/w/3.jpg", history: [], using: &generator)
        let afterLast = WallpaperPicker.next(from: wallpapers, order: .sequential, current: "/w/5.jpg", history: [], using: &generator)
        #expect(first?.wallpaperID == "/w/1.jpg")
        #expect(afterThird?.wallpaperID == "/w/4.jpg")
        #expect(afterLast?.wallpaperID == "/w/1.jpg")
    }

    @Test func sequentialUsesNaturalOrder() {
        var generator = SystemRandomNumberGenerator()
        let items = [Wallpaper(path: "/w/10.jpg"), Wallpaper(path: "/w/9.jpg")]
        let pick = WallpaperPicker.next(from: items, order: .sequential, current: nil, history: [], using: &generator)
        #expect(pick?.wallpaperID == "/w/9.jpg")
    }

    @Test(arguments: [CyclingOrder.random, .sequential])
    func avoidsWallpapersOnOtherDisplays(order: CyclingOrder) {
        var generator = SystemRandomNumberGenerator()
        let avoiding: Set = ["/w/1.jpg", "/w/2.jpg", "/w/3.jpg", "/w/4.jpg"]
        for _ in 0..<20 {
            let pick = WallpaperPicker.next(
                from: wallpapers, order: order, current: nil, avoiding: avoiding, history: [], using: &generator)
            #expect(pick?.wallpaperID == "/w/5.jpg")
        }
    }

    @Test func singleCandidateIsReused() {
        var generator = SystemRandomNumberGenerator()
        let only = [Wallpaper(path: "/w/only.jpg")]
        let pick = WallpaperPicker.next(
            from: only, order: .random, current: "/w/only.jpg", avoiding: ["/w/only.jpg"], history: ["/w/only.jpg"],
            using: &generator)
        #expect(pick?.wallpaperID == "/w/only.jpg")
    }

    @Test func noCandidatesPicksNothing() {
        var generator = SystemRandomNumberGenerator()
        #expect(WallpaperPicker.next(from: [], order: .random, current: nil, history: [], using: &generator) == nil)
    }

    @Test func candidatesRespectInclusionAndKeptDownloads() {
        let library = LibraryState(wallpapers: [
            Wallpaper(path: "/w/in.jpg"),
            Wallpaper(path: "/w/out.jpg", includedInCycling: false),
            Wallpaper(path: "/dl/temp.jpg", origin: .wallhaven(id: "t")),
            Wallpaper(path: "/dl/kept.jpg", origin: .wallhaven(id: "k"), isKept: true),
        ])
        #expect(WallpaperPicker.candidates(in: library).map(\.path) == ["/w/in.jpg", "/dl/kept.jpg"])
    }
}

@Suite struct RotationScheduleTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func firstChangeIsDueImmediately() {
        #expect(RotationSchedule.nextChange(after: nil, interval: 600, now: now) == now)
    }

    @Test func nextChangeCountsFromLastChange() {
        let last = now.addingTimeInterval(-100)
        #expect(RotationSchedule.nextChange(after: last, interval: 600, now: now) == last.addingTimeInterval(600))
        #expect(!RotationSchedule.isDue(lastChange: last, interval: 600, now: now))
        #expect(RotationSchedule.isDue(lastChange: last, interval: 100, now: now))
    }

    @Test func intervalHasAMinimum() {
        #expect(RotationSchedule.nextChange(after: now, interval: 1, now: now) == now.addingTimeInterval(60))
    }

    @Test func presetTitles() {
        #expect(IntervalPreset.title(for: 30 * 60) == "30 minutes")
        #expect(IntervalPreset.title(for: 3600) == "1 hour")
    }
}

@Suite @MainActor struct CyclingControllerTests {
    /// A controller with `count` wallpapers and local cycling every 10 minutes.
    private func makeCycling(
        _ harness: ControllerHarness, count: Int = 3, changeAtStartup: Bool = false
    ) async throws -> AppController {
        for index in 1...count {
            try harness.pictures.makeFile("\(index).jpg")
        }
        let setup = harness.makeController()
        await setup.addSources([harness.pictures.url])
        setup.settings.cycling = CyclingSettings(interval: 600, changeAtStartup: changeAtStartup, order: .sequential)
        setup.settings.rotationSource = .local
        setup.setWallpaper(id: harness.pictures.url.appendingPathComponent("1.jpg").path)

        // Start a fresh controller, as on app launch.
        let controller = harness.makeController()
        await controller.start()
        return controller
    }

    private func shown(_ controller: AppController) -> String? {
        controller.currentWallpaper(on: .main).map(\.fileName)
    }

    @Test func changesAtStartupWhenEnabled() async throws {
        let harness = try ControllerHarness()
        let controller = try await makeCycling(harness, changeAtStartup: true)
        #expect(shown(controller) == "2.jpg")
    }

    @Test func keepsWallpaperAtStartupWhenDisabled() async throws {
        let harness = try ControllerHarness()
        let controller = try await makeCycling(harness, changeAtStartup: false)
        #expect(shown(controller) == "1.jpg")
        #expect(controller.nextRotationDate == harness.clock.date.addingTimeInterval(600))
    }

    @Test func overdueChangeIsNotMadeUpAtLaunch() async throws {
        let harness = try ControllerHarness()
        _ = try await makeCycling(harness)
        harness.clock.advance(by: 3 * 3600)

        let relaunched = harness.makeController()
        await relaunched.start()
        #expect(shown(relaunched) == "1.jpg")
        #expect(relaunched.nextRotationDate == harness.clock.date.addingTimeInterval(600))
    }

    @Test func remainingPeriodSurvivesRelaunch() async throws {
        let harness = try ControllerHarness()
        let controller = try await makeCycling(harness)
        let due = try #require(controller.nextRotationDate)
        harness.clock.advance(by: 120)

        let relaunched = harness.makeController()
        await relaunched.start()
        #expect(relaunched.nextRotationDate == due)
    }

    @Test func tickChangesOnlyWhenDue() async throws {
        let harness = try ControllerHarness()
        let controller = try await makeCycling(harness)

        harness.clock.advance(by: 300)
        await controller.rotationTick()
        #expect(shown(controller) == "1.jpg")

        harness.clock.advance(by: 300)
        await controller.rotationTick()
        #expect(shown(controller) == "2.jpg")
        #expect(controller.nextRotationDate == harness.clock.date.addingTimeInterval(600))
    }

    @Test func excludedWallpapersAreSkipped() async throws {
        let harness = try ControllerHarness()
        let controller = try await makeCycling(harness)
        controller.setIncludedInCycling(false, ids: [harness.pictures.url.appendingPathComponent("2.jpg").path])

        await controller.nextWallpaper()
        #expect(shown(controller) == "3.jpg")
    }

    @Test func pausingStopsChanges() async throws {
        let harness = try ControllerHarness()
        let controller = try await makeCycling(harness)
        controller.settings.isRotationPaused = true
        #expect(controller.nextRotationDate == nil)

        harness.clock.advance(by: 3600)
        await controller.rotationTick()
        #expect(shown(controller) == "1.jpg")

        // Resuming restarts the period instead of changing right away.
        controller.settings.isRotationPaused = false
        #expect(controller.nextRotationDate == harness.clock.date.addingTimeInterval(600))
    }

    @Test func perDisplayCyclingPicksDifferentWallpapers() async throws {
        var harness = try ControllerHarness()
        harness.displays = [.main, .external]
        let controller = try await makeCycling(harness)
        controller.settings.displayMode = .perDisplay

        await controller.nextWallpaper()
        let main = controller.currentWallpaper(on: .main)?.id
        let external = controller.currentWallpaper(on: .external)?.id
        #expect(main != nil && external != nil)
        #expect(main != external)
    }

    @Test func deletedCurrentWallpaperIsReplaced() async throws {
        let harness = try ControllerHarness()
        let controller = try await makeCycling(harness)
        try FileManager.default.removeItem(at: harness.pictures.url.appendingPathComponent("1.jpg"))

        await controller.rescan()
        #expect(shown(controller) == "2.jpg")
    }

    @Test func nextWallpaperWorksWithRotationOff() async throws {
        let harness = try ControllerHarness()
        let controller = try await makeCycling(harness)
        controller.settings.rotationSource = .off
        #expect(controller.nextRotationDate == nil)

        await controller.nextWallpaper()
        #expect(shown(controller) == "2.jpg")
    }
}
