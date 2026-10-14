import Foundation

/// Talks to the Wallhaven API and downloads images.
public struct WallhavenClient: Sendable {
    private let session: URLSession
    private let apiKey: String?

    public init(session: URLSession, apiKey: String?) {
        self.session = session
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func search(_ query: WallhavenQuery) async throws -> WallhavenSearchResponse {
        var request = URLRequest(url: query.url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(WallhavenSearchResponse.self, from: data)
    }

    /// Downloads the full image into `folder` and returns its location. An image that was
    /// downloaded before is reused.
    public func download(_ wallpaper: WallhavenWallpaper, to folder: URL) async throws -> URL {
        let destination = folder.appendingPathComponent(wallpaper.path.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        let (data, response) = try await session.data(from: wallpaper.path)
        try Self.check(response)
        if let mimeType = response.mimeType, !mimeType.hasPrefix("image/") {
            throw WallhavenError.notAnImage
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return }
        switch status {
        case 200..<300: return
        case 401: throw WallhavenError.unauthorized
        case 429: throw WallhavenError.rateLimited
        default: throw WallhavenError.httpStatus(status)
        }
    }
}

/// Decides which Wallhaven downloads to delete.
public enum WallhavenRetention {
    /// Downloads beyond the newest `limit` that aren't kept or currently shown.
    public static func downloadsToRemove(in library: LibraryState, limit: Int, shown: Set<Wallpaper.ID>) -> [Wallpaper] {
        let removable = library.wallpapers
            .filter { $0.isWallhaven && !$0.isKept }
            .sorted { $0.dateAdded > $1.dateAdded }
        return removable.dropFirst(max(0, limit)).filter { !shown.contains($0.id) }
    }
}
