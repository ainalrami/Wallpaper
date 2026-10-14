import AppKit
import SwiftUI
import WallpaperCore

/// Loads downscaled images off the main thread and keeps them in memory.
@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 600
    }

    func image(for path: String, maxPixelSize: Int) async -> NSImage? {
        let key = "\(maxPixelSize)|\(path)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let image = ImageInfo.thumbnail(of: URL(fileURLWithPath: path), maxPixelSize: maxPixelSize) else {
                return nil
            }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
        if let loaded {
            cache.setObject(loaded, forKey: key)
        }
        return loaded
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// A wallpaper thumbnail that fills its frame.
struct ThumbnailView: View {
    let path: String
    var maxPixelSize = 480

    // `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode, so State is stored directly.
    private let _image = State<NSImage?>(initialValue: nil)
    private var image: NSImage? {
        get { _image.wrappedValue }
        nonmutating set { _image.wrappedValue = newValue }
    }

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipped()
            .task(id: path) {
                image = await ThumbnailCache.shared.image(for: path, maxPixelSize: maxPixelSize)
            }
    }
}
