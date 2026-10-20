import Foundation
import Testing
@testable import WallpaperCore

@Suite struct SpaceLayoutTests {
    private func space(_ id: Int, uuid: String, type: Int = 0) -> [String: Any] {
        ["ManagedSpaceID": id, "uuid": uuid, "type": type]
    }

    @Test func parsesDesktopsPerDisplay() throws {
        let layout = try #require(SpaceLayout(managedDisplaySpaces: [
            [
                "Display Identifier": "MAIN",
                "Current Space": space(5, uuid: "B"),
                "Spaces": [space(4, uuid: "A"), space(9, uuid: "FULL", type: 4), space(5, uuid: "B")],
            ],
            [
                "Display Identifier": "EXT",
                "Current Space": space(7, uuid: "C"),
                "Spaces": [space(7, uuid: "C")],
            ],
        ]))
        #expect(!layout.spansDisplays)
        #expect(layout.spaces == [
            DesktopSpace(id: "A", number: 1, displayID: "MAIN", isCurrent: false),
            DesktopSpace(id: "B", number: 2, displayID: "MAIN", isCurrent: true),
            DesktopSpace(id: "C", number: 1, displayID: "EXT", isCurrent: true),
        ])
        #expect(layout.currentSpace(on: "MAIN")?.id == "B")
        #expect(layout.spaces(on: "EXT").map(\.id) == ["C"])
    }

    @Test func emptyUUIDFallsBackToManagedID() throws {
        let layout = try #require(SpaceLayout(managedDisplaySpaces: [[
            "Display Identifier": "MAIN",
            "Current Space": space(1, uuid: ""),
            "Spaces": [space(1, uuid: ""), space(2, uuid: "X")],
        ]]))
        #expect(layout.spaces.map(\.id) == ["managed-1", "X"])
        #expect(layout.currentSpace(on: "MAIN")?.id == "managed-1")
    }

    @Test func mainIdentifierMeansSpacesSpanDisplays() throws {
        let layout = try #require(SpaceLayout(managedDisplaySpaces: [[
            "Display Identifier": "Main",
            "Current Space": space(1, uuid: "A"),
            "Spaces": [space(1, uuid: "A"), space(2, uuid: "B")],
        ]]))
        #expect(layout.spansDisplays)
        #expect(layout.spaces(on: "ANY-DISPLAY").count == 2)
        #expect(layout.currentSpace(on: "OTHER")?.id == "A")
    }

    @Test func malformedInputIsNil() {
        #expect(SpaceLayout(managedDisplaySpaces: []) == nil)
        #expect(SpaceLayout(managedDisplaySpaces: [["Display Identifier": "MAIN"]]) == nil)
        #expect(SpaceLayout(managedDisplaySpaces: [[
            "Display Identifier": "MAIN", "Spaces": [space(3, uuid: "F", type: 4)],
        ]]) == nil)
    }
}

@Suite struct TargetContextTests {
    let layout = SpaceLayout(spaces: [
        DesktopSpace(id: "A", number: 1, displayID: "MAIN", isCurrent: true),
        DesktopSpace(id: "B", number: 2, displayID: "MAIN", isCurrent: false),
        DesktopSpace(id: "C", number: 3, displayID: "MAIN", isCurrent: false),
        DesktopSpace(id: "X", number: 1, displayID: "EXT", isCurrent: true),
    ], spansDisplays: false)
    let work = SpaceGroup(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Work", spaceIDs: ["A", "B"])

    private func context(mode: DisplayMode = .same, enabled: Bool = true, layout: SpaceLayout? = nil) -> TargetContext {
        TargetContext(
            displays: [.main, .external], mode: mode, layout: layout ?? self.layout,
            spaceSettings: SpaceSettings(isEnabled: enabled, groups: [work]))
    }

    @Test func groupedAndUngroupedSpaceKeys() {
        let context = context()
        #expect(context.spaceKey(for: "A") == "g:\(work.id.uuidString)")
        #expect(context.spaceKey(for: "C") == "s:C")
        #expect(context.activeKey(for: .main) == "*#g:\(work.id.uuidString)")
    }

    @Test func lookupFallsBackFromSpaceToDisplayToAll() {
        #expect(context(mode: .perDisplay).lookupKeys(for: .external) == ["EXT#s:X", "EXT", "*"])
        #expect(context(mode: .same).lookupKeys(for: .external) == ["*#s:X", "*"])
    }

    @Test func disabledOrUnavailableUsesDisplayKeys() {
        let disabled = context(mode: .perDisplay, enabled: false)
        #expect(!disabled.isPerSpace)
        #expect(disabled.lookupKeys(for: .main) == ["MAIN", "*"])
        #expect(disabled.spaceTargets().isEmpty)

        let unavailable = TargetContext(
            displays: [.main], mode: .same, layout: nil, spaceSettings: SpaceSettings(isEnabled: true))
        #expect(!unavailable.isPerSpace)
        #expect(unavailable.lookupKeys(for: .main) == ["*"])
    }

    @Test func spaceTargetsMergeGroups() {
        let targets = context().spaceTargets()
        #expect(targets.map(\.key) == ["*#g:\(work.id.uuidString)", "*#s:C", "*#s:X"])
        #expect(targets.map(\.title) == ["Built-in · Work", "Built-in · Desktop 3", "Studio Display · Desktop 1"])
    }

    @Test func currentTargetTitles() {
        let single = TargetContext(
            displays: [.main], mode: .same, layout: layout, spaceSettings: SpaceSettings(isEnabled: true))
        #expect(single.currentTarget(for: .main).title == "Desktop 1")
        #expect(context(enabled: false).currentTarget(for: .main).title == "All Displays")
        #expect(context(mode: .perDisplay, enabled: false).currentTarget(for: .external).title == "Studio Display")
    }

    @Test func switchingDisplayModeCarriesSpaceWallpapers() {
        var state = RuntimeState(currentWallpapers: ["*": "base", "*#s:A": "a"])
        state.switchDisplayMode(to: .perDisplay, displays: [.main, .external])
        #expect(state.currentWallpapers["MAIN#s:A"] == "a")
        #expect(state.currentWallpapers["EXT#s:A"] == "a")

        state.currentWallpapers["MAIN#s:B"] = "b"
        state.switchDisplayMode(to: .same, displays: [.main, .external])
        #expect(state.currentWallpapers["*#s:B"] == "b")
    }

    @Test func spaceSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.spaces = SpaceSettings(isEnabled: true, groups: [work])
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).spaces == settings.spaces)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).spaces == SpaceSettings())
    }
}

@Suite @MainActor struct PerSpaceControllerTests {
    /// Four wallpapers, desktops A (current), B, C, and per-Space wallpapers turned on with
    /// `base` shown on every Space.
    private func makePerSpace(_ harness: ControllerHarness) async throws -> AppController {
        for name in ["base", "w1", "w2", "w3"] {
            try harness.pictures.makeFile("\(name).jpg")
        }
        harness.spaces.setDesktops(["A", "B", "C"])
        let controller = harness.makeController()
        await controller.start()
        await controller.addSources([harness.pictures.url])
        controller.setWallpaper(id: path(harness, "base"))
        controller.settings.spaces.isEnabled = true
        return controller
    }

    private func path(_ harness: ControllerHarness, _ name: String) -> String {
        harness.pictures.url.appendingPathComponent("\(name).jpg").path
    }

    private func shown(_ controller: AppController) -> String? {
        controller.currentWallpaper(on: .main)?.url.deletingPathExtension().lastPathComponent
    }

    private func visit(_ space: String, _ harness: ControllerHarness, _ controller: AppController) -> String? {
        harness.spaces.switchTo(space)
        controller.reapplyCurrent()
        return harness.applier.current[Display.main.id]?.url.deletingPathExtension().lastPathComponent
    }

    @Test func settingWallpaperChangesOnlyCurrentSpace() async throws {
        let harness = try ControllerHarness()
        let controller = try await makePerSpace(harness)

        controller.setWallpaper(id: path(harness, "w1"))
        #expect(shown(controller) == "w1")
        #expect(visit("B", harness, controller) == "base")
        #expect(visit("A", harness, controller) == "w1")
    }

    @Test func switchingToUnchangedSpaceDoesNothing() async throws {
        let harness = try ControllerHarness()
        let controller = try await makePerSpace(harness)
        let calls = harness.applier.calls.count

        _ = visit("B", harness, controller)
        #expect(harness.applier.calls.count == calls)
    }

    @Test func groupedSpacesShareWallpaper() async throws {
        let harness = try ControllerHarness()
        let controller = try await makePerSpace(harness)
        controller.setWallpaper(id: path(harness, "w1"))

        // A had w1; the new group takes it, so B shows it too. C keeps its own.
        controller.createSpaceGroup(named: "Work", spaceIDs: ["A", "B"])
        #expect(visit("B", harness, controller) == "w1")
        #expect(visit("C", harness, controller) == "base")

        controller.setWallpaper(id: path(harness, "w2"))
        #expect(visit("C", harness, controller) == "w2")
        #expect(visit("A", harness, controller) == "w1")
    }

    @Test func leavingOrDeletingGroupKeepsWallpaper() async throws {
        let harness = try ControllerHarness()
        let controller = try await makePerSpace(harness)
        let group = controller.createSpaceGroup(named: "Work", spaceIDs: ["A", "B"])
        controller.setWallpaper(id: path(harness, "w1"))

        controller.setSpaceGroup(nil, forSpace: "B")
        #expect(visit("B", harness, controller) == "w1")
        controller.setWallpaper(id: path(harness, "w2"))
        #expect(visit("A", harness, controller) == "w1")

        controller.deleteSpaceGroup(id: group.id)
        #expect(controller.settings.spaces.groups.isEmpty)
        #expect(visit("A", harness, controller) == "w1")
        #expect(!controller.runtime.currentWallpapers.keys.contains { $0.contains("#g:") })
    }

    @Test func settingInactiveSpaceAppliesOnVisit() async throws {
        let harness = try ControllerHarness()
        let controller = try await makePerSpace(harness)
        let target = try #require(controller.targetContext.spaceTargets().first { $0.title == "Desktop 3" })
        let calls = harness.applier.calls.count

        controller.setWallpaper(id: path(harness, "w3"), target: target)
        #expect(harness.applier.calls.count == calls)
        #expect(visit("C", harness, controller) == "w3")
    }

    @Test func allSpacesReplacesPerSpaceWallpapers() async throws {
        let harness = try ControllerHarness()
        let controller = try await makePerSpace(harness)
        controller.setWallpaper(id: path(harness, "w1"))
        _ = visit("B", harness, controller)
        controller.setWallpaper(id: path(harness, "w2"))

        controller.setWallpaperOnAllSpaces(id: path(harness, "w3"))
        #expect(!controller.runtime.currentWallpapers.keys.contains { $0.contains("#") })
        #expect(shown(controller) == "w3")
        #expect(visit("A", harness, controller) == "w3")
    }

    @Test func rotationGivesEachSpaceItsOwnWallpaper() async throws {
        let harness = try ControllerHarness()
        let controller = try await makePerSpace(harness)
        controller.settings.cycling = CyclingSettings(interval: 600, order: .random)
        let calls = harness.applier.calls.count

        await controller.nextWallpaper()
        // Only the visible Space changes now.
        #expect(harness.applier.calls.count == calls + 1)

        var seen: [String?] = []
        for space in ["A", "B", "C"] {
            harness.spaces.switchTo(space)
            controller.refreshDisplaysAndSpaces()
            seen.append(controller.currentWallpaper(on: .main)?.id)
        }
        #expect(seen.allSatisfy { $0 != nil })
        #expect(Set(seen).count == 3)
    }

    @Test func unavailableSpacesBehaveAsBefore() async throws {
        let harness = try ControllerHarness()
        let controller = try await makePerSpace(harness)
        harness.spaces.set(nil)
        controller.refreshDisplaysAndSpaces()

        controller.setWallpaper(id: path(harness, "w1"))
        #expect(controller.runtime.currentWallpapers["*"] == path(harness, "w1"))
        #expect(!controller.targetContext.isPerSpace)
    }
}
