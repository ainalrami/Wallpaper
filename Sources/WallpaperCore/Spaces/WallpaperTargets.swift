import Foundation

/// A place a wallpaper can be assigned: all displays, one display, or a Space or group of Spaces.
public struct WallpaperTarget: Identifiable, Hashable, Sendable {
    /// The key in `RuntimeState.currentWallpapers`.
    public var key: String
    public var title: String
    /// Keys to look up, most specific first, when this target has no wallpaper of its own.
    public var lookupKeys: [String]

    public var id: String { key }
}

/// Works out assignment keys from the displays, the display mode, and the Spaces.
///
/// Keys are `*` (all displays) or a display UUID. With per-Space wallpapers they get a suffix:
/// `<display key>#g:<group ID>` for a group, or `<display key>#s:<Space ID>` for a single Space.
public struct TargetContext: Sendable {
    public var displays: [Display]
    public var mode: DisplayMode
    public var layout: SpaceLayout?
    public var spaceSettings: SpaceSettings

    public init(displays: [Display], mode: DisplayMode, layout: SpaceLayout?, spaceSettings: SpaceSettings) {
        self.displays = displays
        self.mode = mode
        self.layout = layout
        self.spaceSettings = spaceSettings
    }

    /// Whether wallpapers are assigned per Space: turned on, and the Spaces could be read.
    public var isPerSpace: Bool { spaceSettings.isEnabled && layout != nil }

    public func displayKey(for display: Display) -> String {
        mode == .same ? RuntimeState.allDisplaysKey : display.id
    }

    /// The group key for a grouped Space, otherwise the Space's own key.
    public func spaceKey(for spaceID: DesktopSpace.ID) -> String {
        if let group = spaceSettings.group(containing: spaceID) {
            return "g:\(group.id.uuidString)"
        }
        return "s:\(spaceID)"
    }

    public func key(display: Display, spaceID: DesktopSpace.ID) -> String {
        "\(displayKey(for: display))#\(spaceKey(for: spaceID))"
    }

    /// The key whose wallpaper should be on `display` right now.
    public func activeKey(for display: Display) -> String {
        if isPerSpace, let space = layout?.currentSpace(on: display.id) {
            return key(display: display, spaceID: space.id)
        }
        return displayKey(for: display)
    }

    /// Keys to look up for `display`, most specific first.
    public func lookupKeys(for display: Display) -> [String] {
        unique([activeKey(for: display), displayKey(for: display), RuntimeState.allDisplaysKey])
    }

    /// The target shown on `display` right now.
    public func currentTarget(for display: Display) -> WallpaperTarget {
        guard isPerSpace, let space = layout?.currentSpace(on: display.id) else {
            let key = displayKey(for: display)
            return WallpaperTarget(
                key: key, title: mode == .same ? "All Displays" : display.name, lookupKeys: lookupKeys(for: display))
        }
        return spaceTarget(display: display, space: space)
    }

    /// Every Space target (one per group or ungrouped Space) on the displays, in display order.
    public func spaceTargets() -> [WallpaperTarget] {
        guard isPerSpace, let layout else { return [] }
        var seen = Set<String>()
        var targets: [WallpaperTarget] = []
        for display in displays {
            for space in layout.spaces(on: display.id) {
                let target = spaceTarget(display: display, space: space)
                if seen.insert(target.key).inserted {
                    targets.append(target)
                }
            }
        }
        return targets
    }

    private func spaceTarget(display: Display, space: DesktopSpace) -> WallpaperTarget {
        var title = spaceSettings.group(containing: space.id)?.name ?? space.title
        // Name the display when Spaces belong to one of several displays.
        if displays.count > 1, !(layout?.spansDisplays ?? false) || mode == .perDisplay {
            title = "\(display.name) · \(title)"
        }
        let key = key(display: display, spaceID: space.id)
        return WallpaperTarget(
            key: key, title: title,
            lookupKeys: unique([key, displayKey(for: display), RuntimeState.allDisplaysKey]))
    }

    private func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }
}

extension RuntimeState {
    /// The first wallpaper found for `keys`.
    public func wallpaperID(forKeys keys: [String]) -> String? {
        keys.lazy.compactMap { currentWallpapers[$0] }.first
    }

    /// Removes the per-Space wallpapers under `displayKey`, so its Spaces show the base wallpaper.
    public mutating func clearSpaceWallpapers(under displayKey: String) {
        currentWallpapers = currentWallpapers.filter { !$0.key.hasPrefix("\(displayKey)#") }
    }
}
