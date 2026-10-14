import Foundation

/// How a wallpaper image is placed on a display. Mirrors the options in System Settings.
public enum ScalingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit
    case stretch
    case center
    case tile

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fill: "Fill Screen"
        case .fit: "Fit to Screen"
        case .stretch: "Stretch to Fill Screen"
        case .center: "Center"
        case .tile: "Tile"
        }
    }

    /// Whether the mode can leave empty areas that are painted with the fill color.
    public var usesFillColor: Bool {
        self == .fit || self == .center
    }
}

/// A color stored as sRGB components in the 0...1 range.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
}
