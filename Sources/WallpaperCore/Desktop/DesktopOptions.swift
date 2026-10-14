import AppKit

/// The options passed to `NSWorkspace.setDesktopImageURL(_:for:options:)`.
public struct DesktopOptions: Equatable, Sendable {
    public var scaling: NSImageScaling
    public var allowClipping: Bool
    /// Color for the areas the image doesn't cover. `nil` when the mode never shows it.
    public var fillColor: RGBAColor?

    public init(scaling: NSImageScaling, allowClipping: Bool, fillColor: RGBAColor? = nil) {
        self.scaling = scaling
        self.allowClipping = allowClipping
        self.fillColor = fillColor
    }

    /// The options that produce `mode`. Tile has no system option: the image is pre-rendered
    /// at the display's size and shown with fill options.
    public init(mode: ScalingMode, fillColor: RGBAColor) {
        switch mode {
        case .fill, .tile:
            self.init(scaling: .scaleProportionallyUpOrDown, allowClipping: true)
        case .fit:
            self.init(scaling: .scaleProportionallyUpOrDown, allowClipping: false, fillColor: fillColor)
        case .stretch:
            self.init(scaling: .scaleAxesIndependently, allowClipping: true)
        case .center:
            self.init(scaling: .scaleNone, allowClipping: true, fillColor: fillColor)
        }
    }

    /// Reads options back from the dictionary returned by `NSWorkspace.desktopImageOptions(for:)`.
    public init(workspaceOptions: [NSWorkspace.DesktopImageOptionKey: Any]) {
        let rawScaling = (workspaceOptions[.imageScaling] as? NSNumber)?.uintValue
        scaling = rawScaling.flatMap(NSImageScaling.init(rawValue:)) ?? .scaleProportionallyUpOrDown
        allowClipping = (workspaceOptions[.allowClipping] as? NSNumber)?.boolValue ?? true
        fillColor = (workspaceOptions[.fillColor] as? NSColor).flatMap(RGBAColor.init(nsColor:))
    }

    public var workspaceOptions: [NSWorkspace.DesktopImageOptionKey: Any] {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: scaling.rawValue),
            .allowClipping: NSNumber(value: allowClipping),
        ]
        if let fillColor {
            options[.fillColor] = fillColor.nsColor
        }
        return options
    }

    /// Whether the desktop would look the same with `other`. The fill color only matters
    /// when this value sets one, and colors are compared at 8-bit precision.
    public func matches(_ other: DesktopOptions) -> Bool {
        guard scaling == other.scaling, allowClipping == other.allowClipping else { return false }
        guard let fillColor else { return true }
        guard let otherColor = other.fillColor else { return false }
        return fillColor.isClose(to: otherColor)
    }
}

extension RGBAColor {
    public init?(nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        )
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func isClose(to other: RGBAColor) -> Bool {
        let tolerance = 1.0 / 255.0
        return abs(red - other.red) <= tolerance
            && abs(green - other.green) <= tolerance
            && abs(blue - other.blue) <= tolerance
            && abs(alpha - other.alpha) <= tolerance
    }
}
