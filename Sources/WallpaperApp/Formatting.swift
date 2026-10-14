import SwiftUI
import WallpaperCore

extension ScalingMode {
    var systemImage: String {
        switch self {
        case .fill: "arrow.up.left.and.arrow.down.right"
        case .fit: "arrow.down.right.and.arrow.up.left"
        case .stretch: "arrow.left.and.right"
        case .center: "dot.square"
        case .tile: "square.grid.3x3"
        }
    }
}

extension RGBAColor {
    var color: Color { Color(nsColor: nsColor) }

    init(_ color: Color) {
        self = RGBAColor(nsColor: NSColor(color)) ?? .black
    }
}
