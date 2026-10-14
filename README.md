# Wallpaper Manager

A native macOS menu bar app for managing desktop wallpapers. It adds what System Settings lacks:

- **A live library** built from the folders and images you choose. Images added to or deleted from those folders appear in or disappear from the app automatically.
- **A scaling mode for each wallpaper.** Fill, fit, stretch, center, or tile, plus a fill color for fit and center, is remembered per wallpaper and applied whenever that wallpaper is shown.
- **Configurable cycling:** period, which wallpapers are included, random or sequential order, and whether to change at startup.
- **[Wallhaven](https://wallhaven.cc) as a source:** keywords, minimum resolution, categories, purity, period, and whether to change at startup.
- **Displays:** the same wallpaper on all displays, or a different one per display.

## Using the app

1. **Choose wallpapers.** The library window opens on first launch, and again whenever every image in the library has been deleted. Pick a folder (optionally with subfolders) or individual images. More sources can be added with **Add Source** at the bottom of the sidebar.
2. **Set a mode per wallpaper.** Select a wallpaper and use the inspector on the right. The preview shows how it will look on your display. Double-click a thumbnail to set it as the wallpaper.
3. **Automatic changes.** In **Settings → Cycling**, choose the source that changes the wallpaper: **Off**, **Local Cycling**, or **Wallhaven**. Only one runs at a time; each keeps its own period and "change when the app starts" setting. To leave a wallpaper out of cycling, turn off **Include in cycling** in the inspector, or use a source's context menu to include or exclude all of its images.
4. **Wallhaven.** In **Settings → Wallhaven**, enter comma-separated keywords (one is chosen at random for each change), a minimum resolution, and categories. Downloads are saved to `~/Pictures/Wallpaper Manager/Wallhaven` by default and use the default mode set there. Older downloads are deleted automatically; choose **Keep** on a download to keep it. Kept downloads are also shown by local cycling. An API key is only needed for NSFW results and is stored in the keychain.
5. **Menu bar.** Shows the current wallpaper and has **Next Wallpaper**, **Pause/Resume**, and the time of the next change. Turn on **Settings → General → Open at login** to keep rotation running.

The app's data is in `~/Library/Application Support/WallpaperManager`.

### Known limitations

- macOS only lets apps change the wallpaper of the **active Space**. The app re-applies the wallpaper when you switch Spaces, so another Space may show its old wallpaper for a moment.
- The app is signed ad hoc, not with a Developer ID. The first time, open it with right-click → **Open**. Open at login works best when the app is in `/Applications`.

## Requirements

- macOS 14 or later
- Swift 6.4 via [swiftly](https://github.com/swiftlang/swiftly), pinned in `.swift-version`. Xcode isn't required.

## Development

```sh
git config core.hooksPath .githooks   # enable the pre-commit test hook (once per clone)
scripts/test.sh                       # build and run all tests
scripts/build-app.sh                  # build "dist/Wallpaper Manager.app"
open "dist/Wallpaper Manager.app"
```

- `Sources/WallpaperCore` holds all of the logic (library, desktop, rotation, Wallhaven, persistence). It is covered by tests in `Tests/WallpaperCoreTests`, written with Swift Testing.
- `Sources/WallpaperApp` is the SwiftUI app: menu bar, library window, and settings.
- `scripts/make-icon.swift` generates `Resources/AppIcon.icns`.

> **Note:** With Command Line Tools only, SwiftUI's `@State` macro doesn't build (its plugin ships with Xcode), so views store `State` explicitly. Avoid other SwiftUI macros such as `@Entry` and `#Preview`.
