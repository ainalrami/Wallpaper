import Foundation

/// A folder or single image the user added to the library.
public struct LibrarySource: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case folder
        case file
    }

    public var id: UUID
    public var kind: Kind
    public var path: String
    public var includeSubfolders: Bool
    /// Bookmark data used to find the item again if it is moved.
    public var bookmark: Data?

    public init(id: UUID = UUID(), kind: Kind, path: String, includeSubfolders: Bool = false, bookmark: Data? = nil) {
        self.id = id
        self.kind = kind
        self.path = path
        self.includeSubfolders = includeSubfolders
        self.bookmark = bookmark
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var displayName: String { url.lastPathComponent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        path = try c.decode(String.self, forKey: .path)
        includeSubfolders = try c.decode(Bool.self, forKey: .includeSubfolders, default: false)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
    }
}

/// Where a wallpaper came from.
public enum WallpaperOrigin: Codable, Hashable, Sendable {
    /// Found in one of the user's library sources.
    case local
    /// Downloaded from Wallhaven; the associated value is the Wallhaven wallpaper ID.
    case wallhaven(id: String)
}

/// One image in the library together with the settings remembered for it.
public struct Wallpaper: Codable, Hashable, Identifiable, Sendable {
    /// The standardized file path, which uniquely identifies the wallpaper.
    public var id: String { path }
    public var path: String
    public var origin: WallpaperOrigin
    public var mode: ScalingMode
    public var fillColor: RGBAColor
    public var includedInCycling: Bool
    /// Protects a Wallhaven download from automatic cleanup.
    public var isKept: Bool
    public var dateAdded: Date

    public init(
        path: String,
        origin: WallpaperOrigin = .local,
        mode: ScalingMode = .fill,
        fillColor: RGBAColor = .black,
        includedInCycling: Bool = true,
        isKept: Bool = false,
        dateAdded: Date = Date()
    ) {
        self.path = path
        self.origin = origin
        self.mode = mode
        self.fillColor = fillColor
        self.includedInCycling = includedInCycling
        self.isKept = isKept
        self.dateAdded = dateAdded
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var fileName: String { url.lastPathComponent }

    public var isWallhaven: Bool {
        if case .wallhaven = origin { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case path, origin, mode, fillColor, includedInCycling, isKept, dateAdded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        origin = try c.decode(WallpaperOrigin.self, forKey: .origin, default: .local)
        mode = try c.decode(ScalingMode.self, forKey: .mode, default: .fill)
        fillColor = try c.decode(RGBAColor.self, forKey: .fillColor, default: .black)
        includedInCycling = try c.decode(Bool.self, forKey: .includedInCycling, default: true)
        isKept = try c.decode(Bool.self, forKey: .isKept, default: false)
        dateAdded = try c.decode(Date.self, forKey: .dateAdded, default: Date())
    }
}

/// Everything the library persists: the sources and the wallpapers found in them.
public struct LibraryState: Codable, Equatable, Sendable {
    public var sources: [LibrarySource]
    public var wallpapers: [Wallpaper]

    public init(sources: [LibrarySource] = [], wallpapers: [Wallpaper] = []) {
        self.sources = sources
        self.wallpapers = wallpapers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = try c.decode([LibrarySource].self, forKey: .sources, default: [])
        wallpapers = try c.decode([Wallpaper].self, forKey: .wallpapers, default: [])
    }
}
