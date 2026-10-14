import Foundation

/// One search result from the Wallhaven API.
public struct WallhavenWallpaper: Decodable, Equatable, Sendable {
    public var id: String
    /// Page on wallhaven.cc.
    public var url: URL
    /// Full-resolution image.
    public var path: URL
    public var resolution: String
    public var fileType: String?
    public var thumbs: Thumbs?

    public struct Thumbs: Decodable, Equatable, Sendable {
        public var large: URL?
        public var original: URL?
        public var small: URL?
    }

    enum CodingKeys: String, CodingKey {
        case id, url, path, resolution, thumbs
        case fileType = "file_type"
    }
}

public struct WallhavenSearchResponse: Decodable, Equatable, Sendable {
    public var data: [WallhavenWallpaper]
    public var meta: Meta

    /// `query` isn't decoded: the API returns it as a string or as an object.
    public struct Meta: Decodable, Equatable, Sendable {
        public var currentPage: Int
        public var lastPage: Int
        public var seed: String?

        enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case lastPage = "last_page"
            case seed
        }
    }
}

public enum WallhavenError: Error, Equatable, LocalizedError {
    case rateLimited
    case unauthorized
    case httpStatus(Int)
    case noResults
    case notAnImage

    public var errorDescription: String? {
        switch self {
        case .rateLimited: "Wallhaven's rate limit was reached. Trying again shortly."
        case .unauthorized: "Wallhaven rejected the API key. Check it in Settings."
        case .httpStatus(let status): "Wallhaven returned an error (HTTP \(status))."
        case .noResults: "Wallhaven found no wallpapers for these settings."
        case .notAnImage: "Wallhaven returned something that isn't an image."
        }
    }
}

/// The parameters of one search request.
public struct WallhavenQuery: Equatable, Sendable {
    public var keyword: String?
    public var categories: Set<WallhavenSettings.Category>
    public var purity: Set<WallhavenSettings.Purity>
    public var minimumResolution: Resolution?
    public var page: Int
    /// Keeps random results stable across pages.
    public var seed: String

    public init(settings: WallhavenSettings, keyword: String?, page: Int = 1, seed: String) {
        self.keyword = keyword
        categories = settings.categories
        purity = settings.purity
        minimumResolution = settings.minimumResolution
        self.page = page
        self.seed = seed
    }

    public static let searchURL = URL(string: "https://wallhaven.cc/api/v1/search")!

    public var url: URL {
        var components = URLComponents(url: Self.searchURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "categories", value: Self.bits(WallhavenSettings.Category.allCases, in: categories)),
            URLQueryItem(name: "purity", value: Self.bits(WallhavenSettings.Purity.allCases, in: purity)),
            URLQueryItem(name: "sorting", value: "random"),
            URLQueryItem(name: "seed", value: seed),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let keyword, !keyword.isEmpty {
            items.insert(URLQueryItem(name: "q", value: keyword), at: 0)
        }
        if let minimumResolution {
            items.append(URLQueryItem(name: "atleast", value: minimumResolution.description))
        }
        components.queryItems = items
        // URLComponents leaves "+" unescaped, but Wallhaven reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// Wallhaven's flag format: one digit per option, e.g. `110`. An empty set falls back to the first option.
    static func bits<T: Hashable>(_ all: [T], in selected: Set<T>) -> String {
        let effective = selected.isEmpty ? [all[0]] : selected
        return all.map { effective.contains($0) ? "1" : "0" }.joined()
    }

    public static func makeSeed() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<6).map { _ in characters.randomElement()! })
    }
}

extension WallhavenSettings {
    /// Keywords with surrounding spaces removed and empty entries dropped.
    public var cleanedKeywords: [String] {
        keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    public var downloadFolder: URL {
        downloadFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? AppPaths.defaultWallhavenFolder
    }
}
