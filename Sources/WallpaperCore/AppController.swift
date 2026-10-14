import Foundation
import Observation

/// Coordinates the library, settings, and desktop. The UI reads and changes state through it.
@MainActor @Observable public final class AppController {
    public private(set) var library: LibraryState
    public private(set) var runtime: RuntimeState
    public private(set) var displays: [Display] = []
    /// `true` once the sources have been scanned after launch.
    public private(set) var hasScanned = false
    /// The most recent problem, shown to the user until dismissed.
    public var statusMessage: String?
    /// When the active rotation source changes the wallpaper next. `nil` when rotation is off or paused.
    public private(set) var nextRotationDate: Date?

    public var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    /// Called when the library ends up empty, so the UI can show onboarding.
    @ObservationIgnored public var onLibraryEmpty: (() -> Void)?

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let desktop: DesktopService
    @ObservationIgnored private let scanner = LibraryScanner()
    @ObservationIgnored private let settingsStore: JSONStore<AppSettings>
    @ObservationIgnored private let libraryStore: JSONStore<LibraryState>
    @ObservationIgnored private let runtimeStore: JSONStore<RuntimeState>
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var needsAnotherScan = false
    @ObservationIgnored private var rotationTask: Task<Void, Never>?

    public init(environment: AppEnvironment) {
        self.environment = environment
        settingsStore = JSONStore(fileURL: environment.paths.settingsFile)
        libraryStore = JSONStore(fileURL: environment.paths.libraryFile)
        runtimeStore = JSONStore(fileURL: environment.paths.runtimeFile)
        settings = settingsStore.load(default: AppSettings())
        library = libraryStore.load(default: LibraryState())
        runtime = runtimeStore.load(default: RuntimeState())
        desktop = DesktopService(
            applier: environment.applier,
            tileRenderer: environment.tileRenderer,
            displayProvider: environment.displayProvider,
            variantsDirectory: environment.paths.cacheDirectory.appendingPathComponent("Variants"))
    }

    // MARK: - Lifecycle

    /// Whether the user needs to choose wallpapers: nothing was ever added, or every image is gone.
    public var needsOnboarding: Bool {
        library.wallpapers.isEmpty && (hasScanned || library.sources.isEmpty)
    }

    /// Finds moved sources, starts watching folders, and scans the library.
    public func start() async {
        displays = environment.displayProvider.displays()
        if library.resolveMovedSources() {
            saveLibrary()
        }
        startWatching()
        await rescan()
        await startRotation()
    }

    /// Scans all sources and updates the library. Calls made during a scan are merged into one more scan.
    public func rescan() async {
        guard !isScanning else {
            needsAnotherScan = true
            return
        }
        isScanning = true
        defer { isScanning = false }

        repeat {
            needsAnotherScan = false
            let sources = library.sources
            let scanner = scanner
            let paths = await Task.detached { scanner.scan(sources) }.value
            guard library.sources == sources else {
                needsAnotherScan = true
                continue
            }
            applyScan(paths)
        } while needsAnotherScan
    }

    private func applyScan(_ paths: Set<String>) {
        let wasEmpty = library.wallpapers.isEmpty
        let result = LibraryReconciler.reconcile(
            library, scannedPaths: paths,
            defaults: WallpaperDefaults(mode: settings.defaultMode, fillColor: settings.defaultFillColor),
            now: environment.now())
        let firstScan = !hasScanned
        hasScanned = true

        if result.hasChanges {
            let removedCurrent = !Set(result.removed).isDisjoint(with: runtime.currentWallpapers.values)
            library = result.state
            saveLibrary()
            for path in result.removed {
                runtime.forgetWallpaper(path)
            }
            if !result.removed.isEmpty {
                saveRuntime()
            }
            // Replace a deleted wallpaper right away when cycling is on.
            if removedCurrent, isRotating(.local), !library.wallpapers.isEmpty {
                rotateLocal()
                scheduleRotation()
            }
        }
        if library.wallpapers.isEmpty, firstScan || !wasEmpty {
            onLibraryEmpty?()
        }
    }

    private func startWatching() {
        environment.watcher.watch(paths: library.watchedPaths) { [weak self] in
            Task { @MainActor in await self?.rescan() }
        }
    }

    // MARK: - Sources

    /// Adds folders and images. Folders are scanned with `includeSubfolders`.
    public func addSources(_ urls: [URL], includeSubfolders: Bool = false) async {
        var changed = false
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if library.addSource(at: url, isDirectory: isDirectory.boolValue, includeSubfolders: includeSubfolders) != nil {
                changed = true
            }
        }
        guard changed else { return }
        saveLibrary()
        startWatching()
        await rescan()
    }

    public func removeSource(id: LibrarySource.ID) async {
        library.removeSource(id: id)
        saveLibrary()
        startWatching()
        await rescan()
    }

    public func setIncludeSubfolders(_ include: Bool, for sourceID: LibrarySource.ID) async {
        guard let index = library.sources.firstIndex(where: { $0.id == sourceID }) else { return }
        library.sources[index].includeSubfolders = include
        saveLibrary()
        await rescan()
    }

    // MARK: - Wallpapers

    /// Changes a wallpaper's saved settings and updates any display that shows it.
    public func updateWallpaper(id: Wallpaper.ID, _ update: (inout Wallpaper) -> Void) {
        guard let before = library.wallpaper(id: id) else { return }
        library.updateWallpaper(id: id, update)
        guard let after = library.wallpaper(id: id), after != before else { return }
        saveLibrary()

        if after.mode != before.mode || after.fillColor != before.fillColor {
            for display in displays where runtime.wallpaperID(for: display, mode: settings.displayMode) == id {
                apply(after, to: display)
            }
        }
    }

    public func setIncludedInCycling(_ included: Bool, ids: [Wallpaper.ID]) {
        for id in ids {
            library.updateWallpaper(id: id) { $0.includedInCycling = included }
        }
        saveLibrary()
    }

    /// Shows a wallpaper. `displayID == nil` shows it on every display.
    public func setWallpaper(id: Wallpaper.ID, displayID: String? = nil) {
        guard let wallpaper = library.wallpaper(id: id) else { return }
        displays = environment.displayProvider.displays()
        runtime.setWallpaper(id, for: displayID, mode: settings.displayMode, displays: displays)
        saveRuntime()

        let targets = settings.displayMode == .perDisplay && displayID != nil
            ? displays.filter { $0.id == displayID }
            : displays
        for display in targets {
            apply(wallpaper, to: display)
        }
    }

    /// The wallpaper currently shown on `display`.
    public func currentWallpaper(on display: Display) -> Wallpaper? {
        runtime.wallpaperID(for: display, mode: settings.displayMode).flatMap(library.wallpaper(id:))
    }

    // MARK: - Displays

    /// Re-applies assigned wallpapers to displays that don't show them, e.g. after a display is
    /// connected or the user switches to another Space.
    public func reapplyCurrent() {
        displays = environment.displayProvider.displays()
        let errors = desktop.applyAssigned(
            state: runtime, library: library, mode: settings.displayMode, displays: displays, onlyIfChanged: true)
        if let error = errors.first {
            report(error)
        }
    }

    private func apply(_ wallpaper: Wallpaper, to display: Display) {
        do {
            try desktop.apply(wallpaper, to: display)
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Rotation

    /// Shows the next wallpaper from the active source, or from local cycling when rotation is off.
    public func nextWallpaper() async {
        await rotate(using: settings.rotationSource == .off ? .local : settings.rotationSource)
        scheduleRotation()
    }

    /// Changes the wallpaper if the active source is due. Called by the timer and after the Mac wakes.
    public func rotationTick() async {
        let source = settings.rotationSource
        if isRotating(source), let interval = interval(for: source),
           RotationSchedule.isDue(lastChange: lastChange(for: source), interval: interval, now: environment.now()) {
            await rotate(using: source)
        }
        scheduleRotation()
    }

    /// Applies "change at startup", then starts the timer.
    private func startRotation() async {
        let source = settings.rotationSource
        guard isRotating(source), let interval = interval(for: source) else {
            scheduleRotation()
            return
        }
        if changesAtStartup(source) {
            await rotate(using: source)
        } else if RotationSchedule.isDue(lastChange: lastChange(for: source), interval: interval, now: environment.now()) {
            // Without "change at startup", time spent while the app wasn't running doesn't count.
            setLastChange(environment.now(), for: source)
        }
        scheduleRotation()
    }

    /// Restarts the timer for the active source's next change.
    public func scheduleRotation() {
        rotationTask?.cancel()
        let source = settings.rotationSource
        guard isRotating(source), let interval = interval(for: source) else {
            nextRotationDate = nil
            return
        }
        let now = environment.now()
        let next = RotationSchedule.nextChange(after: lastChange(for: source), interval: interval, now: now)
        nextRotationDate = next
        let delay = max(0, next.timeIntervalSince(now))
        rotationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.rotationTick()
        }
    }

    private func rotate(using source: RotationSource) async {
        switch source {
        case .off: break
        case .local: rotateLocal()
        case .wallhaven: break
        }
    }

    /// Picks the next included wallpaper, a different one per display in per-display mode.
    private func rotateLocal() {
        defer { setLastChange(environment.now(), for: .local) }
        let candidates = WallpaperPicker.candidates(in: library)
        guard !candidates.isEmpty else {
            statusMessage = "No wallpapers are included in cycling."
            return
        }
        displays = environment.displayProvider.displays()
        var generator = SystemRandomNumberGenerator()
        var history = runtime.cyclingHistory

        if settings.displayMode == .perDisplay {
            var picked = Set<Wallpaper.ID>()
            for display in displays {
                guard let pick = WallpaperPicker.next(
                    from: candidates, order: settings.cycling.order,
                    current: runtime.wallpaperID(for: display, mode: .perDisplay),
                    avoiding: picked, history: history, using: &generator) else { continue }
                history = pick.history
                picked.insert(pick.wallpaperID)
                setWallpaper(id: pick.wallpaperID, displayID: display.id)
            }
        } else if let pick = WallpaperPicker.next(
            from: candidates, order: settings.cycling.order,
            current: runtime.currentWallpapers[RuntimeState.allDisplaysKey],
            history: history, using: &generator) {
            history = pick.history
            setWallpaper(id: pick.wallpaperID)
        }
        runtime.cyclingHistory = history
    }

    private func isRotating(_ source: RotationSource) -> Bool {
        source != .off && source == settings.rotationSource && !settings.isRotationPaused
    }

    private func interval(for source: RotationSource) -> TimeInterval? {
        switch source {
        case .off: nil
        case .local: settings.cycling.interval
        case .wallhaven: settings.wallhaven.interval
        }
    }

    private func changesAtStartup(_ source: RotationSource) -> Bool {
        switch source {
        case .off: false
        case .local: settings.cycling.changeAtStartup
        case .wallhaven: settings.wallhaven.changeAtStartup
        }
    }

    private func lastChange(for source: RotationSource) -> Date? {
        switch source {
        case .off: nil
        case .local: runtime.lastLocalChange
        case .wallhaven: runtime.lastWallhavenChange
        }
    }

    private func setLastChange(_ date: Date, for source: RotationSource) {
        switch source {
        case .off: return
        case .local: runtime.lastLocalChange = date
        case .wallhaven: runtime.lastWallhavenChange = date
        }
        saveRuntime()
    }

    // MARK: - Settings

    private func settingsDidChange(from old: AppSettings) {
        guard settings != old else { return }
        saveSettings()
        if settings.displayMode != old.displayMode {
            displays = environment.displayProvider.displays()
            runtime.switchDisplayMode(to: settings.displayMode, displays: displays)
            saveRuntime()
            reapplyCurrent()
        }

        let sourceChanged = settings.rotationSource != old.rotationSource
        let resumed = old.isRotationPaused && !settings.isRotationPaused
        if sourceChanged || resumed {
            // Count the period from now rather than from an old change or the pause.
            setLastChange(environment.now(), for: settings.rotationSource)
        }
        if sourceChanged || settings.isRotationPaused != old.isRotationPaused
            || settings.cycling.interval != old.cycling.interval
            || settings.wallhaven.interval != old.wallhaven.interval {
            scheduleRotation()
        }
    }

    // MARK: - Persistence

    private func saveSettings() { save { try settingsStore.save(settings) } }
    private func saveLibrary() { save { try libraryStore.save(library) } }
    private func saveRuntime() { save { try runtimeStore.save(runtime) } }

    private func save(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            statusMessage = "Couldn't save changes: \(error.localizedDescription)"
        }
    }
}
