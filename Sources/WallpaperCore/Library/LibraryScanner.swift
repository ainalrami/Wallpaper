import Foundation

/// Finds the image files that belong to library sources.
public struct LibraryScanner: Sendable {
    /// File extensions the desktop can display.
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp",
    ]

    public init() {}

    public static func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Standardized paths of every supported image in `sources`.
    public func scan(_ sources: [LibrarySource]) -> Set<String> {
        sources.reduce(into: Set<String>()) { result, source in
            result.formUnion(scan(source))
        }
    }

    public func scan(_ source: LibrarySource) -> [String] {
        let fileManager = FileManager.default
        switch source.kind {
        case .file:
            let url = source.url.standardizedFileURL
            guard Self.isSupportedImage(url), fileManager.fileExists(atPath: url.path) else { return [] }
            return [url.path]
        case .folder:
            var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            if !source.includeSubfolders {
                options.insert(.skipsSubdirectoryDescendants)
            }
            guard let enumerator = fileManager.enumerator(
                at: source.url.standardizedFileURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: options
            ) else { return [] }

            var paths: [String] = []
            for case let url as URL in enumerator where Self.isSupportedImage(url) {
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                if isFile {
                    paths.append(url.standardizedFileURL.path)
                }
            }
            return paths.sorted()
        }
    }
}
