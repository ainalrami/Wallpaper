import Foundation
import Testing
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
    let secrets = InMemorySecretStore()
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
            httpSession: MockURLProtocol.makeSession(),
            secrets: secrets,
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

final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func read(account: String) -> String? {
        lock.withLock { values[account] }
    }

    func write(_ value: String?, account: String) throws {
        lock.withLock { values[account] = (value?.isEmpty ?? true) ? nil : value }
    }
}

/// Answers URL requests from a handler instead of the network.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status = 200
        var mimeType = "application/json"
        var body = Data()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> Response)?
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) -> Response) {
        lock.withLock {
            self.handler = handler
            recorded = []
        }
    }

    static var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self.recorded.append(request)
            return Self.handler
        }
        let response = handler?(request) ?? Response(status: 500)
        let http = HTTPURLResponse(
            url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": response.mimeType])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
