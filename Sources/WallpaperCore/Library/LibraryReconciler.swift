import Foundation

/// Defaults applied to wallpapers that are found for the first time.
public struct WallpaperDefaults: Sendable {
    public var mode: ScalingMode
    public var fillColor: RGBAColor

    public init(mode: ScalingMode = .fill, fillColor: RGBAColor = .black) {
        self.mode = mode
        self.fillColor = fillColor
    }
}

public struct ReconcileResult: Equatable, Sendable {
    public var state: LibraryState
    public var added: [String]
    public var removed: [String]

    public var hasChanges: Bool { !added.isEmpty || !removed.isEmpty }
}

/// Brings the saved library in line with the files that exist on disk.
public enum LibraryReconciler {
    /// - Parameters:
    ///   - scannedPaths: images currently found in the user's sources.
    ///   - fileExists: used to check Wallhaven downloads, which live outside the user's sources.
    public static func reconcile(
        _ state: LibraryState,
        scannedPaths: Set<String>,
        defaults: WallpaperDefaults,
        now: Date = Date(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> ReconcileResult {
        var kept: [Wallpaper] = []
        var keptPaths = Set<String>()
        var removed: [String] = []

        for wallpaper in state.wallpapers where !keptPaths.contains(wallpaper.path) {
            let stillExists = scannedPaths.contains(wallpaper.path)
                || (wallpaper.isWallhaven && fileExists(wallpaper.path))
            if stillExists {
                kept.append(wallpaper)
                keptPaths.insert(wallpaper.path)
            } else {
                removed.append(wallpaper.path)
            }
        }

        let added = scannedPaths.subtracting(keptPaths).sorted()
        for path in added {
            kept.append(Wallpaper(path: path, mode: defaults.mode, fillColor: defaults.fillColor, dateAdded: now))
        }

        var newState = state
        newState.wallpapers = kept
        return ReconcileResult(state: newState, added: added, removed: removed)
    }
}

extension LibraryState {
    /// Adds a folder or image as a source. Returns `nil` if it is already a source.
    @discardableResult
    public mutating func addSource(at url: URL, isDirectory: Bool, includeSubfolders: Bool = false) -> LibrarySource? {
        let path = url.standardizedFileURL.path
        guard !sources.contains(where: { $0.path == path }) else { return nil }
        let source = LibrarySource(
            kind: isDirectory ? .folder : .file,
            path: path,
            includeSubfolders: includeSubfolders,
            bookmark: try? url.bookmarkData()
        )
        sources.append(source)
        return source
    }

    public mutating func removeSource(id: LibrarySource.ID) {
        sources.removeAll { $0.id == id }
    }

    /// Updates sources whose path no longer exists but whose bookmark resolves to a new location.
    /// Returns `true` if any source changed.
    @discardableResult
    public mutating func resolveMovedSources() -> Bool {
        var changed = false
        for index in sources.indices {
            let source = sources[index]
            guard !FileManager.default.fileExists(atPath: source.path), let bookmark = source.bookmark else { continue }
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            sources[index].path = url.standardizedFileURL.path
            if isStale {
                sources[index].bookmark = try? url.bookmarkData()
            }
            changed = true
        }
        return changed
    }

    /// The folders to watch for changes: folder sources and the parent folders of image sources.
    public var watchedPaths: [String] {
        let paths = sources.map { source in
            source.kind == .folder ? source.path : source.url.deletingLastPathComponent().path
        }
        return Array(Set(paths)).sorted()
    }

    public func wallpaper(id: Wallpaper.ID) -> Wallpaper? {
        wallpapers.first { $0.id == id }
    }

    public mutating func updateWallpaper(id: Wallpaper.ID, _ update: (inout Wallpaper) -> Void) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        update(&wallpapers[index])
    }

    /// Local wallpapers that belong to the given source.
    public func wallpapers(in source: LibrarySource) -> [Wallpaper] {
        switch source.kind {
        case .file:
            return wallpapers.filter { $0.path == source.path }
        case .folder:
            let prefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
            return wallpapers.filter { wallpaper in
                guard !wallpaper.isWallhaven, wallpaper.path.hasPrefix(prefix) else { return false }
                return source.includeSubfolders || !wallpaper.path.dropFirst(prefix.count).contains("/")
            }
        }
    }
}
