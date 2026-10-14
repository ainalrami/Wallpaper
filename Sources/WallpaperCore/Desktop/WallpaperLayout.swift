import CoreGraphics

/// Where an image is drawn on a display for each scaling mode. Used to preview modes.
public enum WallpaperLayout {
    /// The rectangles the image occupies inside `canvas`, which represents a display of
    /// `displayPixelSize`. Rectangles may extend past the canvas and should be clipped.
    public static func imageRects(
        mode: ScalingMode, imageSize: CGSize, canvas: CGRect, displayPixelSize: CGSize
    ) -> [CGRect] {
        guard imageSize.width > 0, imageSize.height > 0, canvas.width > 0, canvas.height > 0 else { return [] }

        switch mode {
        case .fill:
            let scale = max(canvas.width / imageSize.width, canvas.height / imageSize.height)
            return [centered(CGSize(width: imageSize.width * scale, height: imageSize.height * scale), in: canvas)]
        case .fit:
            let scale = min(canvas.width / imageSize.width, canvas.height / imageSize.height)
            return [centered(CGSize(width: imageSize.width * scale, height: imageSize.height * scale), in: canvas)]
        case .stretch:
            return [canvas]
        case .center:
            return [centered(actualSize(imageSize, canvas: canvas, displayPixelSize: displayPixelSize), in: canvas)]
        case .tile:
            let tile = actualSize(imageSize, canvas: canvas, displayPixelSize: displayPixelSize)
            guard tile.width >= 0.5, tile.height >= 0.5 else { return [canvas] }
            var rects: [CGRect] = []
            var y = canvas.minY
            while y < canvas.maxY {
                var x = canvas.minX
                while x < canvas.maxX {
                    rects.append(CGRect(origin: CGPoint(x: x, y: y), size: tile))
                    x += tile.width
                }
                y += tile.height
            }
            return rects
        }
    }

    /// The image's unscaled size on the display, converted into canvas units.
    private static func actualSize(_ imageSize: CGSize, canvas: CGRect, displayPixelSize: CGSize) -> CGSize {
        let scale = displayPixelSize.width > 0 ? canvas.width / displayPixelSize.width : 1
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private static func centered(_ size: CGSize, in canvas: CGRect) -> CGRect {
        CGRect(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2, width: size.width, height: size.height)
    }
}
