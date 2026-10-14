import Foundation

/// The services `AppController` depends on. Tests replace them with fakes.
@MainActor public struct AppEnvironment {
    public var paths: AppPaths
    public var watcher: FileSystemWatching
    public var applier: DesktopApplying
    public var displayProvider: DisplayProviding
    public var tileRenderer: TileRendering
    public var httpSession: URLSession
    public var secrets: SecretStoring
    public var now: @Sendable () -> Date

    public init(
        paths: AppPaths,
        watcher: FileSystemWatching,
        applier: DesktopApplying,
        displayProvider: DisplayProviding,
        tileRenderer: TileRendering,
        httpSession: URLSession = .shared,
        secrets: SecretStoring = KeychainSecretStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.watcher = watcher
        self.applier = applier
        self.displayProvider = displayProvider
        self.tileRenderer = tileRenderer
        self.httpSession = httpSession
        self.secrets = secrets
        self.now = now
    }

    public static func live() -> AppEnvironment {
        let paths = AppPaths.standard
        return AppEnvironment(
            paths: paths,
            watcher: DirectoryWatcher(),
            applier: WorkspaceDesktopApplier(),
            displayProvider: ScreenDisplayProvider(),
            tileRenderer: TileRenderer(cacheDirectory: paths.cacheDirectory.appendingPathComponent("Tiles"))
        )
    }
}
