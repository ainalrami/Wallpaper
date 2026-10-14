import AppKit
import CoreGraphics

/// A connected display, identified by a UUID that stays the same across reboots.
public struct Display: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var isMain: Bool

    public init(id: String, name: String, pixelWidth: Int, pixelHeight: Int, isMain: Bool = false) {
        self.id = id
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isMain = isMain
    }

    public var aspectRatio: Double {
        pixelHeight == 0 ? 16.0 / 9.0 : Double(pixelWidth) / Double(pixelHeight)
    }
}

public protocol DisplayProviding: Sendable {
    @MainActor func displays() -> [Display]
}

/// Reads the connected displays from `NSScreen`.
public struct ScreenDisplayProvider: DisplayProviding {
    public init() {}

    @MainActor public func displays() -> [Display] {
        let main = NSScreen.main
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.displayUUID else { return nil }
            return Display(
                id: id,
                name: screen.localizedName,
                pixelWidth: Int(screen.frame.width * screen.backingScaleFactor),
                pixelHeight: Int(screen.frame.height * screen.backingScaleFactor),
                isMain: screen == main
            )
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The display's persistent UUID string.
    var displayUUID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
