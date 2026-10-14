import Foundation
import Testing
@testable import WallpaperCore

@Suite struct PersistenceTests {
    @Test func settingsRoundTrip() throws {
        let dir = try TemporaryDirectory()
        let store = JSONStore<AppSettings>(fileURL: dir.url.appendingPathComponent("settings.json"))
        var settings = AppSettings()
        settings.displayMode = .perDisplay
        settings.rotationSource = .wallhaven
        settings.cycling = CyclingSettings(interval: 120, changeAtStartup: true, order: .sequential)
        settings.wallhaven.keywords = ["mountains", "space"]
        settings.wallhaven.minimumResolution = Resolution(width: 2560, height: 1440)
        settings.wallhaven.purity = [.sfw, .sketchy]

        try store.save(settings)
        #expect(store.load(default: AppSettings()) == settings)
    }

    @Test func libraryRoundTripKeepsPerWallpaperSettings() throws {
        let dir = try TemporaryDirectory()
        let store = JSONStore<LibraryState>(fileURL: dir.url.appendingPathComponent("library.json"))
        let source = LibrarySource(kind: .folder, path: "/tmp/walls", includeSubfolders: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let state = LibraryState(sources: [source], wallpapers: [
            Wallpaper(path: "/tmp/walls/a.jpg", mode: .fit, fillColor: RGBAColor(red: 1, green: 0, blue: 0), dateAdded: date),
            Wallpaper(path: "/tmp/w/b.png", origin: .wallhaven(id: "abc123"), mode: .tile,
                      includedInCycling: false, isKept: true, dateAdded: date),
        ])

        try store.save(state)
        #expect(store.load(default: LibraryState()) == state)
    }

    @Test func missingFileLoadsDefault() throws {
        let dir = try TemporaryDirectory()
        let store = JSONStore<AppSettings>(fileURL: dir.url.appendingPathComponent("nope.json"))
        #expect(store.load(default: AppSettings()) == AppSettings())
    }

    @Test func corruptFileLoadsDefaultAndIsBackedUp() throws {
        let dir = try TemporaryDirectory()
        let file = try dir.makeFile("settings.json", contents: Data("{ not json".utf8))
        let store = JSONStore<AppSettings>(fileURL: file)

        #expect(store.load(default: AppSettings()) == AppSettings())
        #expect(FileManager.default.fileExists(atPath: file.path + ".corrupt"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func missingFieldsUseDefaults() throws {
        let dir = try TemporaryDirectory()
        let json = #"{ "displayMode": "perDisplay", "wallhaven": { "keywords": ["sea"] } }"#
        let file = try dir.makeFile("settings.json", contents: Data(json.utf8))
        let loaded = JSONStore<AppSettings>(fileURL: file).load(default: AppSettings())

        #expect(loaded.displayMode == .perDisplay)
        #expect(loaded.wallhaven.keywords == ["sea"])
        #expect(loaded.wallhaven.retentionLimit == WallhavenSettings().retentionLimit)
        #expect(loaded.cycling == CyclingSettings())
    }

    @Test func wallpaperWithOnlyPathDecodes() throws {
        let json = #"{ "path": "/a/b.jpg" }"#
        let wallpaper = try JSONDecoder().decode(Wallpaper.self, from: Data(json.utf8))
        #expect(wallpaper.mode == .fill)
        #expect(wallpaper.origin == .local)
        #expect(wallpaper.includedInCycling)
    }

    @Test func scalingModeFillColorUsage() {
        #expect(ScalingMode.allCases.filter(\.usesFillColor) == [.fit, .center])
    }

    @Test func resolutionFormatsForWallhaven() {
        #expect(Resolution(width: 3840, height: 2160).description == "3840x2160")
    }
}
