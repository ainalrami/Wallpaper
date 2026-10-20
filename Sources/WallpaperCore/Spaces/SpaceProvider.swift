import Foundation

/// Reports the desktops of every display.
public protocol SpaceProviding: Sendable {
    /// `nil` when Spaces can't be read.
    @MainActor func layout() -> SpaceLayout?
}

/// Reads Spaces through SkyLight, the window server framework. macOS has no public API for
/// Spaces, so the private functions are looked up at runtime. If a macOS update removes them,
/// `layout()` returns `nil` and the app uses one wallpaper for all Spaces.
public final class SkyLightSpaceProvider: SpaceProviding, @unchecked Sendable {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let connection: Int32?
    private let copySpaces: CopyManagedDisplaySpaces?

    public init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainConnection = dlsym(handle, "CGSMainConnectionID"),
              let copySpaces = dlsym(handle, "CGSCopyManagedDisplaySpaces") else {
            connection = nil
            copySpaces = nil
            return
        }
        connection = unsafeBitCast(mainConnection, to: MainConnectionID.self)()
        self.copySpaces = unsafeBitCast(copySpaces, to: CopyManagedDisplaySpaces.self)
    }

    @MainActor public func layout() -> SpaceLayout? {
        guard let connection, let copySpaces,
              let displays = copySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return SpaceLayout(managedDisplaySpaces: displays)
    }
}
