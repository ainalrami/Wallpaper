import AppKit

/// Sets and reads the desktop picture of a display.
@MainActor public protocol DesktopApplying: AnyObject {
    func currentImage(for displayID: String) -> (url: URL, options: DesktopOptions)?
    func setImage(_ url: URL, options: DesktopOptions, for displayID: String) throws
}

/// Applies desktop pictures through `NSWorkspace`.
@MainActor public final class WorkspaceDesktopApplier: DesktopApplying {
    public init() {}

    public func currentImage(for displayID: String) -> (url: URL, options: DesktopOptions)? {
        guard let screen = screen(for: displayID), let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        return (url, DesktopOptions(workspaceOptions: options))
    }

    public func setImage(_ url: URL, options: DesktopOptions, for displayID: String) throws {
        guard let screen = screen(for: displayID) else { throw DesktopError.displayNotFound(displayID) }
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options.workspaceOptions)
    }

    private func screen(for displayID: String) -> NSScreen? {
        NSScreen.screens.first { $0.displayUUID == displayID }
    }
}

/// Puts library wallpapers on displays using each wallpaper's own mode and fill color.
@MainActor public final class DesktopService {
    private let applier: DesktopApplying
    private let tileRenderer: TileRendering
    private let displayProvider: DisplayProviding
    private let variantsDirectory: URL

    public init(
        applier: DesktopApplying, tileRenderer: TileRendering, displayProvider: DisplayProviding, variantsDirectory: URL
    ) {
        self.applier = applier
        self.tileRenderer = tileRenderer
        self.displayProvider = displayProvider
        self.variantsDirectory = variantsDirectory
    }

    /// - Parameter onlyIfChanged: skip displays that already show the wallpaper with the same options.
    public func apply(_ wallpaper: Wallpaper, to display: Display, onlyIfChanged: Bool = false) throws {
        guard FileManager.default.fileExists(atPath: wallpaper.path) else {
            throw DesktopError.unreadableImage(wallpaper.path)
        }
        let options = DesktopOptions(mode: wallpaper.mode, fillColor: wallpaper.fillColor)
        var imageURL = wallpaper.mode == .tile
            ? try tileRenderer.tiledImage(for: wallpaper.url, pixelWidth: display.pixelWidth, pixelHeight: display.pixelHeight)
            : wallpaper.url

        if let current = applier.currentImage(for: display.id) {
            let currentURL = current.url.standardizedFileURL
            let showsImage = currentURL == imageURL.standardizedFileURL || currentURL == variantURL(for: imageURL)
            if onlyIfChanged, showsImage, options.matches(current.options) {
                return
            }
            // macOS ignores new options when the image URL doesn't change, so show the same
            // file through another name when only the options differ.
            if currentURL == imageURL.standardizedFileURL, !options.matches(current.options) {
                imageURL = try variant(of: imageURL)
            }
        }
        try applier.setImage(imageURL, options: options, for: display.id)
    }

    /// Applies the wallpaper assigned to every display and returns the errors that occurred.
    @discardableResult
    public func applyAssigned(
        state: RuntimeState, library: LibraryState, mode: DisplayMode, displays: [Display], onlyIfChanged: Bool = false
    ) -> [Error] {
        var errors: [Error] = []
        for display in displays {
            guard let id = state.wallpaperID(for: display, mode: mode), let wallpaper = library.wallpaper(id: id) else {
                continue
            }
            do {
                try apply(wallpaper, to: display, onlyIfChanged: onlyIfChanged)
            } catch {
                errors.append(error)
            }
        }
        return errors
    }

    private func variantURL(for url: URL) -> URL {
        variantsDirectory.appendingPathComponent("variant-\(TileRenderer.pathKey(for: url)).\(url.pathExtension)")
            .standardizedFileURL
    }

    /// A hard link (or copy, across volumes) of `url` with a different file name.
    private func variant(of url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: variantsDirectory, withIntermediateDirectories: true)
        let target = variantURL(for: url)
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }

        // Variants are only needed while they are on screen; delete the rest.
        let shown = Set(displayProvider.displays().compactMap {
            applier.currentImage(for: $0.id)?.url.standardizedFileURL.lastPathComponent
        })
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: variantsDirectory.path)) ?? []
        for file in existing where file.hasPrefix("variant-") && !shown.contains(file) {
            try? FileManager.default.removeItem(at: variantsDirectory.appendingPathComponent(file))
        }
        do {
            try FileManager.default.linkItem(at: url, to: target)
        } catch {
            try FileManager.default.copyItem(at: url, to: target)
        }
        return target
    }
}

extension RuntimeState {
    /// The wallpaper that should be on `display`. In per-display mode, a display without its
    /// own wallpaper (for example one that was just connected) shows the shared one.
    public func wallpaperID(for display: Display, mode: DisplayMode) -> String? {
        switch mode {
        case .same:
            currentWallpapers[Self.allDisplaysKey]
        case .perDisplay:
            currentWallpapers[display.id] ?? currentWallpapers[Self.allDisplaysKey]
        }
    }

    /// Records `wallpaperID` as current. `displayID == nil` means every display.
    public mutating func setWallpaper(_ wallpaperID: String, for displayID: String?, mode: DisplayMode, displays: [Display]) {
        switch (mode, displayID) {
        case (.perDisplay, let displayID?):
            currentWallpapers[displayID] = wallpaperID
        default:
            currentWallpapers[Self.allDisplaysKey] = wallpaperID
            for display in displays {
                currentWallpapers[display.id] = wallpaperID
            }
        }
    }

    /// Keeps the desktop unchanged when switching modes: per-display starts from the shared
    /// wallpaper, and "same" takes the main display's wallpaper.
    public mutating func switchDisplayMode(to newMode: DisplayMode, displays: [Display]) {
        switch newMode {
        case .perDisplay:
            if let shared = currentWallpapers[Self.allDisplaysKey] {
                for display in displays where currentWallpapers[display.id] == nil {
                    currentWallpapers[display.id] = shared
                }
            }
        case .same:
            let main = displays.first(where: \.isMain) ?? displays.first
            if let main, let id = currentWallpapers[main.id] {
                currentWallpapers[Self.allDisplaysKey] = id
            }
        }
    }

    /// Forgets a wallpaper that left the library.
    public mutating func forgetWallpaper(_ wallpaperID: String) {
        currentWallpapers = currentWallpapers.filter { $0.value != wallpaperID }
        cyclingHistory.removeAll { $0 == wallpaperID }
    }
}
