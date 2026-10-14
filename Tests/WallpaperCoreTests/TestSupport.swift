import Foundation

/// A temporary directory that is deleted when the value is deinitialized.
final class TemporaryDirectory: @unchecked Sendable {
    let url: URL

    init() throws {
        // Resolve symlinks (/var -> /private/var) so paths match what FSEvents and enumerators report.
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
        url = base.appendingPathComponent("WallpaperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func makeFile(_ relativePath: String, contents: Data = Data([0])) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL)
        return fileURL
    }
}
