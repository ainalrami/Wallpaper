import Foundation

/// Loads and saves one Codable value as a JSON file.
public struct JSONStore<Value: Codable>: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Returns the saved value, or `defaultValue` if there is no file. A file that can't be
    /// decoded is moved aside to `<name>.corrupt` so it isn't silently overwritten.
    public func load(default defaultValue: @autoclosure () -> Value) -> Value {
        guard let data = try? Data(contentsOf: fileURL) else { return defaultValue() }
        do {
            return try Self.decoder.decode(Value.self, from: data)
        } catch {
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return defaultValue()
        }
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Locations of the app's files.
public struct AppPaths: Sendable {
    public let supportDirectory: URL

    public init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    /// `~/Library/Application Support/WallpaperManager`
    public static var standard: AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(supportDirectory: base.appendingPathComponent("WallpaperManager", isDirectory: true))
    }

    public var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }
    public var libraryFile: URL { supportDirectory.appendingPathComponent("library.json") }
    public var runtimeFile: URL { supportDirectory.appendingPathComponent("state.json") }
    public var cacheDirectory: URL { supportDirectory.appendingPathComponent("Cache", isDirectory: true) }

    /// `~/Pictures/Wallpaper Manager/Wallhaven`
    public static var defaultWallhavenFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wallpaper Manager", isDirectory: true)
            .appendingPathComponent("Wallhaven", isDirectory: true)
    }
}
