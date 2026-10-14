import Foundation

/// Whether all displays share one wallpaper or each display has its own.
public enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case same
    case perDisplay

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .same: "Same on All Displays"
        case .perDisplay: "Different per Display"
        }
    }
}

/// The source that changes the wallpaper automatically. Only one can be active.
public enum RotationSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case local
    case wallhaven

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .local: "Local Cycling"
        case .wallhaven: "Wallhaven"
        }
    }
}

public enum CyclingOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case random
    case sequential

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .random: "Random"
        case .sequential: "In Order"
        }
    }
}

public struct CyclingSettings: Codable, Equatable, Sendable {
    /// Seconds between changes.
    public var interval: TimeInterval
    public var changeAtStartup: Bool
    public var order: CyclingOrder

    public init(interval: TimeInterval = 30 * 60, changeAtStartup: Bool = false, order: CyclingOrder = .random) {
        self.interval = interval
        self.changeAtStartup = changeAtStartup
        self.order = order
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CyclingSettings()
        interval = try c.decode(TimeInterval.self, forKey: .interval, default: defaults.interval)
        changeAtStartup = try c.decode(Bool.self, forKey: .changeAtStartup, default: defaults.changeAtStartup)
        order = try c.decode(CyclingOrder.self, forKey: .order, default: defaults.order)
    }
}

public struct Resolution: Codable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Formatted the way Wallhaven expects, e.g. `1920x1080`.
    public var description: String { "\(width)x\(height)" }
}

public struct WallhavenSettings: Codable, Equatable, Sendable {
    public enum Category: String, Codable, CaseIterable, Identifiable, Sendable {
        case general, anime, people
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public enum Purity: String, Codable, CaseIterable, Identifiable, Sendable {
        case sfw, sketchy, nsfw
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .sfw: "SFW"
            case .sketchy: "Sketchy"
            case .nsfw: "NSFW"
            }
        }
        /// NSFW results are only returned to requests that include an API key.
        public var requiresAPIKey: Bool { self == .nsfw }
    }

    public var keywords: [String]
    public var minimumResolution: Resolution?
    public var categories: Set<Category>
    public var purity: Set<Purity>
    public var interval: TimeInterval
    public var changeAtStartup: Bool
    public var defaultMode: ScalingMode
    public var defaultFillColor: RGBAColor
    /// Folder where downloads are stored. `nil` means the default location.
    public var downloadFolderPath: String?
    /// How many downloads that aren't kept are retained before the oldest are deleted.
    public var retentionLimit: Int

    public init(
        keywords: [String] = [],
        minimumResolution: Resolution? = Resolution(width: 1920, height: 1080),
        categories: Set<Category> = [.general],
        purity: Set<Purity> = [.sfw],
        interval: TimeInterval = 60 * 60,
        changeAtStartup: Bool = false,
        defaultMode: ScalingMode = .fill,
        defaultFillColor: RGBAColor = .black,
        downloadFolderPath: String? = nil,
        retentionLimit: Int = 30
    ) {
        self.keywords = keywords
        self.minimumResolution = minimumResolution
        self.categories = categories
        self.purity = purity
        self.interval = interval
        self.changeAtStartup = changeAtStartup
        self.defaultMode = defaultMode
        self.defaultFillColor = defaultFillColor
        self.downloadFolderPath = downloadFolderPath
        self.retentionLimit = retentionLimit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WallhavenSettings()
        keywords = try c.decode([String].self, forKey: .keywords, default: d.keywords)
        minimumResolution = try c.decodeIfPresent(Resolution.self, forKey: .minimumResolution)
        categories = try c.decode(Set<Category>.self, forKey: .categories, default: d.categories)
        purity = try c.decode(Set<Purity>.self, forKey: .purity, default: d.purity)
        interval = try c.decode(TimeInterval.self, forKey: .interval, default: d.interval)
        changeAtStartup = try c.decode(Bool.self, forKey: .changeAtStartup, default: d.changeAtStartup)
        defaultMode = try c.decode(ScalingMode.self, forKey: .defaultMode, default: d.defaultMode)
        defaultFillColor = try c.decode(RGBAColor.self, forKey: .defaultFillColor, default: d.defaultFillColor)
        downloadFolderPath = try c.decodeIfPresent(String.self, forKey: .downloadFolderPath)
        retentionLimit = try c.decode(Int.self, forKey: .retentionLimit, default: d.retentionLimit)
    }
}

/// User preferences.
public struct AppSettings: Codable, Equatable, Sendable {
    public var displayMode: DisplayMode
    /// Mode given to newly found local wallpapers.
    public var defaultMode: ScalingMode
    public var defaultFillColor: RGBAColor
    public var rotationSource: RotationSource
    public var isRotationPaused: Bool
    public var cycling: CyclingSettings
    public var wallhaven: WallhavenSettings

    public init(
        displayMode: DisplayMode = .same,
        defaultMode: ScalingMode = .fill,
        defaultFillColor: RGBAColor = .black,
        rotationSource: RotationSource = .off,
        isRotationPaused: Bool = false,
        cycling: CyclingSettings = CyclingSettings(),
        wallhaven: WallhavenSettings = WallhavenSettings()
    ) {
        self.displayMode = displayMode
        self.defaultMode = defaultMode
        self.defaultFillColor = defaultFillColor
        self.rotationSource = rotationSource
        self.isRotationPaused = isRotationPaused
        self.cycling = cycling
        self.wallhaven = wallhaven
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        displayMode = try c.decode(DisplayMode.self, forKey: .displayMode, default: d.displayMode)
        defaultMode = try c.decode(ScalingMode.self, forKey: .defaultMode, default: d.defaultMode)
        defaultFillColor = try c.decode(RGBAColor.self, forKey: .defaultFillColor, default: d.defaultFillColor)
        rotationSource = try c.decode(RotationSource.self, forKey: .rotationSource, default: d.rotationSource)
        isRotationPaused = try c.decode(Bool.self, forKey: .isRotationPaused, default: d.isRotationPaused)
        cycling = try c.decode(CyclingSettings.self, forKey: .cycling, default: d.cycling)
        wallhaven = try c.decode(WallhavenSettings.self, forKey: .wallhaven, default: d.wallhaven)
    }
}

/// State the app keeps between launches that isn't a user preference.
public struct RuntimeState: Codable, Equatable, Sendable {
    /// The wallpaper shown on each display, keyed by display UUID. In "same" mode the
    /// key `RuntimeState.allDisplaysKey` is used.
    public var currentWallpapers: [String: String]
    public var lastLocalChange: Date?
    public var lastWallhavenChange: Date?
    /// Wallpaper IDs already shown in the current random cycle.
    public var cyclingHistory: [String]
    /// Wallhaven IDs already downloaded, so they aren't fetched again.
    public var seenWallhavenIDs: [String]

    public static let allDisplaysKey = "*"

    public init(
        currentWallpapers: [String: String] = [:],
        lastLocalChange: Date? = nil,
        lastWallhavenChange: Date? = nil,
        cyclingHistory: [String] = [],
        seenWallhavenIDs: [String] = []
    ) {
        self.currentWallpapers = currentWallpapers
        self.lastLocalChange = lastLocalChange
        self.lastWallhavenChange = lastWallhavenChange
        self.cyclingHistory = cyclingHistory
        self.seenWallhavenIDs = seenWallhavenIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentWallpapers = try c.decode([String: String].self, forKey: .currentWallpapers, default: [:])
        lastLocalChange = try c.decodeIfPresent(Date.self, forKey: .lastLocalChange)
        lastWallhavenChange = try c.decodeIfPresent(Date.self, forKey: .lastWallhavenChange)
        cyclingHistory = try c.decode([String].self, forKey: .cyclingHistory, default: [])
        seenWallhavenIDs = try c.decode([String].self, forKey: .seenWallhavenIDs, default: [])
    }
}
