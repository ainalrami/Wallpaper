import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum DesktopError: Error, Equatable, LocalizedError {
    case displayNotFound(String)
    case unreadableImage(String)
    case renderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .displayNotFound: "The display is no longer connected."
        case .unreadableImage(let path): "Couldn't read the image \(URL(fileURLWithPath: path).lastPathComponent)."
        case .renderFailed(let path): "Couldn't render a tiled version of \(URL(fileURLWithPath: path).lastPathComponent)."
        }
    }
}

public protocol TileRendering: Sendable {
    /// Returns an image of `pixelWidth` x `pixelHeight` with `source` repeated from the top-left corner.
    func tiledImage(for source: URL, pixelWidth: Int, pixelHeight: Int) throws -> URL
}

/// Renders tiled wallpapers into a cache folder and reuses them while the source is unchanged.
public struct TileRenderer: TileRendering {
    public let cacheDirectory: URL

    public init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
    }

    public func tiledImage(for source: URL, pixelWidth: Int, pixelHeight: Int) throws -> URL {
        let output = cacheDirectory.appendingPathComponent(
            "tile-\(Self.cacheKey(for: source))-\(pixelWidth)x\(pixelHeight).png")
        if FileManager.default.fileExists(atPath: output.path) {
            return output
        }

        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let tile = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw DesktopError.unreadableImage(source.path)
        }
        guard let image = Self.render(tile: tile, pixelWidth: pixelWidth, pixelHeight: pixelHeight) else {
            throw DesktopError.renderFailed(source.path)
        }

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        removeOutdatedRenders(of: source)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw DesktopError.renderFailed(source.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DesktopError.renderFailed(source.path)
        }
        return output
    }

    static func render(tile: CGImage, pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        guard pixelWidth > 0, pixelHeight > 0, tile.width > 0, tile.height > 0,
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        // Core Graphics' origin is bottom-left; start rows at the top so tiling begins top-left.
        var y = pixelHeight - tile.height
        while y > -tile.height {
            var x = 0
            while x < pixelWidth {
                context.draw(tile, in: CGRect(x: x, y: y, width: tile.width, height: tile.height))
                x += tile.width
            }
            y -= tile.height
        }
        return context.makeImage()
    }

    /// Changes whenever the source file's path, size, or modification date changes.
    static func cacheKey(for source: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return pathKey(for: source) + "-" + String(SHA256.hash(data: Data("\(size)|\(modified)".utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    static func pathKey(for source: URL) -> String {
        String(SHA256.hash(data: Data(source.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// Deletes renders of earlier versions of `source`. Renders for other display sizes are kept.
    private func removeOutdatedRenders(of source: URL) {
        let anyVersion = "tile-\(Self.pathKey(for: source))-"
        let currentVersion = "tile-\(Self.cacheKey(for: source))-"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        for file in files where file.hasPrefix(anyVersion) && !file.hasPrefix(currentVersion) {
            try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(file))
        }
    }
}
