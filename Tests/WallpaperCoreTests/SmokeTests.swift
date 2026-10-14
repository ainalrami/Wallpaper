import Testing
@testable import WallpaperCore

@Test func appIdentityIsDefined() {
    #expect(WallpaperCore.appName == "Wallpaper Manager")
    #expect(!WallpaperCore.bundleIdentifier.isEmpty)
}
