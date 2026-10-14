# Wallpaper Manager

A native macOS menu bar app for managing desktop wallpapers.

- A live library built from the folders and images you choose. Images added to or deleted from those folders appear in or disappear from the app automatically.
- A scaling mode (fill, fit, stretch, center, tile) and fill color remembered for **each** wallpaper.
- Configurable rotation: period, which wallpapers are included, order, and change at startup.
- Optional [Wallhaven](https://wallhaven.cc) source: keywords, minimum resolution, period, and change at startup.
- The same wallpaper on all displays, or a different one per display.

## Requirements

- macOS 14 or later
- Swift 6.4 through [swiftly](https://github.com/swiftlang/swiftly). The toolchain is pinned in `.swift-version`.

## Development

```sh
git config core.hooksPath .githooks   # enable the pre-commit test hook (once per clone)
scripts/test.sh                       # build and run all tests
scripts/build-app.sh                  # build "dist/Wallpaper Manager.app"
open "dist/Wallpaper Manager.app"
```

`Sources/WallpaperCore` holds all of the logic and is covered by tests in `Tests/WallpaperCoreTests` (Swift Testing). `Sources/WallpaperApp` is the SwiftUI app.
