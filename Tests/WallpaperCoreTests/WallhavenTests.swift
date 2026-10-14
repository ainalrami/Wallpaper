import Foundation
import Testing
@testable import WallpaperCore

@Suite struct WallhavenQueryTests {
    private func items(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        return Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
    }

    @Test func buildsSearchParameters() {
        var settings = WallhavenSettings()
        settings.categories = [.general, .people]
        settings.purity = [.sfw, .sketchy]
        settings.minimumResolution = Resolution(width: 2560, height: 1440)
        let url = WallhavenQuery(settings: settings, keyword: "mountains", page: 2, seed: "Ab12Cd").url

        #expect(url.host == "wallhaven.cc")
        #expect(url.path == "/api/v1/search")
        #expect(items(url) == [
            "q": "mountains", "categories": "101", "purity": "110", "sorting": "random",
            "seed": "Ab12Cd", "page": "2", "atleast": "2560x1440",
        ])
    }

    @Test func encodesSpacesAndPlusSigns() {
        let url = WallhavenQuery(settings: WallhavenSettings(), keyword: "+space -anime", seed: "aaaaaa").url
        #expect(url.absoluteString.contains("q=%2Bspace%20-anime"))
    }

    @Test func omitsEmptyKeywordAndResolution() {
        var settings = WallhavenSettings()
        settings.minimumResolution = nil
        let query = items(WallhavenQuery(settings: settings, keyword: nil, seed: "aaaaaa").url)
        #expect(query["q"] == nil)
        #expect(query["atleast"] == nil)
    }

    @Test func emptySelectionsFallBackToFirstOption() {
        var settings = WallhavenSettings()
        settings.categories = []
        settings.purity = []
        let query = items(WallhavenQuery(settings: settings, keyword: nil, seed: "aaaaaa").url)
        #expect(query["categories"] == "100")
        #expect(query["purity"] == "100")
    }

    @Test func seedHasWallhavenFormat() {
        let seed = WallhavenQuery.makeSeed()
        #expect(seed.count == 6)
        #expect(seed.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    @Test func cleansKeywords() {
        let settings = WallhavenSettings(keywords: [" nature ", "", "  ", "city"])
        #expect(settings.cleanedKeywords == ["nature", "city"])
    }

    @Test func decodesSearchResponse() throws {
        let response = try JSONDecoder().decode(WallhavenSearchResponse.self, from: Fixtures.data("wallhaven-search.json"))
        #expect(response.data.map(\.id) == ["abc123", "def456"])
        #expect(response.data[0].path.absoluteString == "https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg")
        #expect(response.data[1].resolution == "2560x1440")
        #expect(response.meta.lastPage == 1)
        #expect(response.meta.seed == "Xy12Ab")
    }
}

@Suite struct WallhavenRetentionTests {
    @Test func removesOldestUnkeptDownloadsBeyondLimit() {
        let base = Date(timeIntervalSince1970: 0)
        func download(_ name: String, age: Double, kept: Bool = false) -> Wallpaper {
            Wallpaper(path: "/dl/\(name).jpg", origin: .wallhaven(id: name), isKept: kept,
                      dateAdded: base.addingTimeInterval(-age))
        }
        let library = LibraryState(wallpapers: [
            download("new", age: 1),
            download("mid", age: 2),
            download("old", age: 3),
            download("oldest", age: 4),
            download("ancient-kept", age: 9, kept: true),
            Wallpaper(path: "/local/a.jpg", dateAdded: base.addingTimeInterval(-100)),
        ])
        let removed = WallhavenRetention.downloadsToRemove(in: library, limit: 2, shown: ["/dl/oldest.jpg"])
        #expect(removed.map(\.path) == ["/dl/old.jpg"])
    }
}

/// Tests that use `MockURLProtocol`, which is shared, so they run one at a time.
@Suite(.serialized) @MainActor struct WallhavenNetworkTests {
    nonisolated static let searchBody = try! Fixtures.data("wallhaven-search.json")

    /// Serves the fixture for searches and image bytes for downloads.
    private func serveFixture(searchStatus: Int = 200) {
        MockURLProtocol.setHandler { request in
            if request.url?.host == "wallhaven.cc" {
                return .init(status: searchStatus, body: searchStatus == 200 ? Self.searchBody : Data())
            }
            return .init(mimeType: "image/jpeg", body: Data("image-bytes".utf8))
        }
    }

    @Test func clientSendsAPIKeyHeader() async throws {
        serveFixture()
        let client = WallhavenClient(session: MockURLProtocol.makeSession(), apiKey: "secret")
        _ = try await client.search(WallhavenQuery(settings: WallhavenSettings(), keyword: nil, seed: "aaaaaa"))
        #expect(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "X-API-Key") == "secret")
    }

    @Test func clientOmitsEmptyAPIKey() async throws {
        serveFixture()
        let client = WallhavenClient(session: MockURLProtocol.makeSession(), apiKey: "")
        _ = try await client.search(WallhavenQuery(settings: WallhavenSettings(), keyword: nil, seed: "aaaaaa"))
        #expect(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "X-API-Key") == nil)
    }

    @Test(arguments: [(429, WallhavenError.rateLimited), (401, .unauthorized), (500, .httpStatus(500))])
    func clientMapsHTTPErrors(status: Int, expected: WallhavenError) async {
        serveFixture(searchStatus: status)
        let client = WallhavenClient(session: MockURLProtocol.makeSession(), apiKey: nil)
        await #expect(throws: expected) {
            try await client.search(WallhavenQuery(settings: WallhavenSettings(), keyword: nil, seed: "aaaaaa"))
        }
    }

    @Test func downloadSavesAndReusesFile() async throws {
        serveFixture()
        let dir = try TemporaryDirectory()
        let client = WallhavenClient(session: MockURLProtocol.makeSession(), apiKey: nil)
        let response = try JSONDecoder().decode(WallhavenSearchResponse.self, from: Self.searchBody)

        let file = try await client.download(response.data[0], to: dir.url)
        #expect(file.lastPathComponent == "wallhaven-abc123.jpg")
        #expect(try Data(contentsOf: file) == Data("image-bytes".utf8))

        let again = try await client.download(response.data[0], to: dir.url)
        #expect(again == file)
        #expect(MockURLProtocol.requests.count == 1)
    }

    @Test func downloadRejectsNonImages() async throws {
        MockURLProtocol.setHandler { _ in .init(mimeType: "text/html", body: Data("<html>".utf8)) }
        let dir = try TemporaryDirectory()
        let client = WallhavenClient(session: MockURLProtocol.makeSession(), apiKey: nil)
        let response = try JSONDecoder().decode(WallhavenSearchResponse.self, from: Self.searchBody)
        await #expect(throws: WallhavenError.notAnImage) {
            try await client.download(response.data[0], to: dir.url)
        }
    }

    // MARK: Controller

    private func makeWallhavenController(_ harness: ControllerHarness) -> AppController {
        let controller = harness.makeController()
        controller.settings.wallhaven.downloadFolderPath = harness.pictures.url.path
        controller.settings.wallhaven.keywords = ["mountains"]
        controller.settings.wallhaven.defaultMode = .fit
        controller.settings.wallhaven.interval = 3600
        controller.settings.rotationSource = .wallhaven
        return controller
    }

    @Test func fetchDownloadsAddsAndAppliesWallpaper() async throws {
        serveFixture()
        let harness = try ControllerHarness()
        let controller = makeWallhavenController(harness)
        controller.wallhavenAPIKey = "key-1"

        await controller.nextWallpaper()

        let shown = try #require(controller.currentWallpaper(on: .main))
        #expect(shown.fileName == "wallhaven-abc123.jpg")
        #expect(shown.origin == .wallhaven(id: "abc123"))
        #expect(shown.mode == .fit)
        #expect(FileManager.default.fileExists(atPath: shown.path))
        #expect(harness.applier.calls.last?.url.lastPathComponent == "wallhaven-abc123.jpg")
        #expect(controller.runtime.seenWallhavenIDs == ["abc123"])
        #expect(controller.nextRotationDate == harness.clock.date.addingTimeInterval(3600))

        let search = try #require(MockURLProtocol.requests.first)
        #expect(search.url?.query?.contains("q=mountains") == true)
        #expect(search.value(forHTTPHeaderField: "X-API-Key") == "key-1")
        #expect(harness.secrets.read(account: AppController.wallhavenAPIKeyAccount) == "key-1")
    }

    @Test func nextFetchSkipsSeenWallpapers() async throws {
        serveFixture()
        let harness = try ControllerHarness()
        let controller = makeWallhavenController(harness)

        await controller.nextWallpaper()
        await controller.nextWallpaper()
        #expect(controller.currentWallpaper(on: .main)?.fileName == "wallhaven-def456.png")

        // Both seen: a repeat is better than nothing.
        await controller.nextWallpaper()
        #expect(controller.currentWallpaper(on: .main) != nil)
        #expect(controller.statusMessage == nil)
    }

    @Test func failedScheduledChangeRetriesAfterAMinute() async throws {
        serveFixture(searchStatus: 429)
        let harness = try ControllerHarness()
        let controller = makeWallhavenController(harness)
        harness.clock.advance(by: 3600)

        await controller.rotationTick()
        #expect(controller.statusMessage == WallhavenError.rateLimited.errorDescription)
        #expect(controller.currentWallpaper(on: .main) == nil)
        #expect(controller.nextRotationDate == harness.clock.date.addingTimeInterval(60))

        // The retry waits for its time even though the change is overdue.
        let requestsBefore = MockURLProtocol.requests.count
        harness.clock.advance(by: 30)
        await controller.rotationTick()
        #expect(MockURLProtocol.requests.count == requestsBefore)

        serveFixture()
        harness.clock.advance(by: 30)
        await controller.rotationTick()
        #expect(controller.currentWallpaper(on: .main)?.fileName == "wallhaven-abc123.jpg")
        #expect(controller.nextRotationDate == harness.clock.date.addingTimeInterval(3600))
    }

    @Test func failedManualFetchKeepsSchedule() async throws {
        serveFixture(searchStatus: 500)
        let harness = try ControllerHarness()
        let controller = makeWallhavenController(harness)
        let scheduled = controller.nextRotationDate

        await controller.nextWallpaper()
        #expect(controller.statusMessage == WallhavenError.httpStatus(500).errorDescription)
        #expect(controller.nextRotationDate == scheduled)
    }

    @Test func successfulFetchClearsEarlierError() async throws {
        serveFixture(searchStatus: 500)
        let harness = try ControllerHarness()
        let controller = makeWallhavenController(harness)
        await controller.nextWallpaper()
        #expect(controller.statusMessage != nil)

        serveFixture()
        await controller.nextWallpaper()
        #expect(controller.statusMessage == nil)
    }

    @Test func oldDownloadsArePrunedButKeptOnesStay() async throws {
        serveFixture()
        let harness = try ControllerHarness()
        let controller = makeWallhavenController(harness)
        controller.settings.wallhaven.retentionLimit = 0

        await controller.nextWallpaper()
        let first = try #require(controller.currentWallpaper(on: .main))
        controller.setKept(true, ids: [first.id])
        harness.clock.advance(by: 10)
        await controller.nextWallpaper()
        let second = try #require(controller.currentWallpaper(on: .main))
        harness.clock.advance(by: 10)
        await controller.nextWallpaper()

        // The kept download stays; the unkept one is deleted once it is no longer shown.
        #expect(controller.library.wallpaper(id: first.id) != nil)
        #expect(FileManager.default.fileExists(atPath: first.path))
        if controller.currentWallpaper(on: .main)?.id != second.id {
            #expect(controller.library.wallpaper(id: second.id) == nil)
            #expect(!FileManager.default.fileExists(atPath: second.path))
        }
    }

    @Test func downloadsSurviveRescan() async throws {
        serveFixture()
        let harness = try ControllerHarness()
        let controller = makeWallhavenController(harness)
        await controller.nextWallpaper()

        await controller.rescan()
        #expect(controller.library.wallpapers.filter(\.isWallhaven).count == 1)
        #expect(harness.watcher.paths.contains(harness.pictures.url.path))
    }
}
