import Foundation
import Testing
@testable import WallpaperCore

@Suite struct LibraryScannerTests {
    @Test func findsOnlySupportedImages() throws {
        let dir = try TemporaryDirectory()
        try dir.makeFile("a.jpg")
        try dir.makeFile("b.PNG")
        try dir.makeFile("c.heic")
        try dir.makeFile("notes.txt")
        try dir.makeFile("doc.pdf")
        try dir.makeFile(".hidden.jpg")

        let source = LibrarySource(kind: .folder, path: dir.url.path)
        let names = LibraryScanner().scan(source).map { URL(fileURLWithPath: $0).lastPathComponent }
        #expect(names == ["a.jpg", "b.PNG", "c.heic"])
    }

    @Test func subfolderOption() throws {
        let dir = try TemporaryDirectory()
        try dir.makeFile("top.jpg")
        try dir.makeFile("nested/deeper/inner.jpg")

        let flat = LibrarySource(kind: .folder, path: dir.url.path, includeSubfolders: false)
        let deep = LibrarySource(kind: .folder, path: dir.url.path, includeSubfolders: true)
        #expect(LibraryScanner().scan(flat).count == 1)
        #expect(LibraryScanner().scan(deep).count == 2)
    }

    @Test func fileSourceRequiresExistingSupportedFile() throws {
        let dir = try TemporaryDirectory()
        let image = try dir.makeFile("one.webp")
        let text = try dir.makeFile("one.txt")

        let scanner = LibraryScanner()
        #expect(scanner.scan(LibrarySource(kind: .file, path: image.path)) == [image.path])
        #expect(scanner.scan(LibrarySource(kind: .file, path: text.path)).isEmpty)
        #expect(scanner.scan(LibrarySource(kind: .file, path: dir.url.appendingPathComponent("gone.jpg").path)).isEmpty)
    }

    @Test func missingFolderScansEmpty() {
        let source = LibrarySource(kind: .folder, path: "/nonexistent/\(UUID().uuidString)")
        #expect(LibraryScanner().scan(source).isEmpty)
    }
}

@Suite struct LibraryReconcilerTests {
    let defaults = WallpaperDefaults(mode: .fit, fillColor: .white)

    @Test func addsNewFilesWithDefaults() {
        let result = LibraryReconciler.reconcile(LibraryState(), scannedPaths: ["/w/a.jpg", "/w/b.jpg"], defaults: defaults)
        #expect(result.added == ["/w/a.jpg", "/w/b.jpg"])
        #expect(result.state.wallpapers.allSatisfy { $0.mode == .fit && $0.fillColor == .white })
    }

    @Test func removesMissingFilesAndKeepsSettings() {
        let state = LibraryState(wallpapers: [
            Wallpaper(path: "/w/a.jpg", mode: .tile, includedInCycling: false),
            Wallpaper(path: "/w/b.jpg", mode: .center),
        ])
        let result = LibraryReconciler.reconcile(state, scannedPaths: ["/w/a.jpg", "/w/c.jpg"], defaults: defaults)

        #expect(result.removed == ["/w/b.jpg"])
        #expect(result.added == ["/w/c.jpg"])
        let a = result.state.wallpaper(id: "/w/a.jpg")
        #expect(a?.mode == .tile)
        #expect(a?.includedInCycling == false)
        #expect(result.state.wallpaper(id: "/w/c.jpg")?.mode == .fit)
    }

    @Test func noChangesWhenUnchanged() {
        let state = LibraryState(wallpapers: [Wallpaper(path: "/w/a.jpg")])
        let result = LibraryReconciler.reconcile(state, scannedPaths: ["/w/a.jpg"], defaults: defaults)
        #expect(!result.hasChanges)
        #expect(result.state == state)
    }

    @Test func wallhavenDownloadsKeptWhileFileExists() {
        let state = LibraryState(wallpapers: [
            Wallpaper(path: "/dl/x.jpg", origin: .wallhaven(id: "x")),
            Wallpaper(path: "/dl/y.jpg", origin: .wallhaven(id: "y")),
        ])
        let result = LibraryReconciler.reconcile(
            state, scannedPaths: [], defaults: defaults, fileExists: { $0 == "/dl/x.jpg" })
        #expect(result.state.wallpapers.map(\.path) == ["/dl/x.jpg"])
        #expect(result.removed == ["/dl/y.jpg"])
    }
}

@Suite struct LibraryStateTests {
    @Test func addSourceRejectsDuplicates() throws {
        let dir = try TemporaryDirectory()
        var state = LibraryState()
        let first = state.addSource(at: dir.url, isDirectory: true)
        let second = state.addSource(at: dir.url, isDirectory: true)
        #expect(first != nil)
        #expect(second == nil)
        #expect(state.sources.count == 1)
        #expect(state.sources[0].bookmark != nil)
    }

    @Test func watchedPathsUseParentForFiles() {
        let state = LibraryState(sources: [
            LibrarySource(kind: .folder, path: "/a"),
            LibrarySource(kind: .file, path: "/b/one.jpg"),
            LibrarySource(kind: .file, path: "/b/two.jpg"),
        ])
        #expect(state.watchedPaths == ["/a", "/b"])
    }

    @Test func wallpapersInSourceRespectSubfolders() {
        var state = LibraryState(wallpapers: [
            Wallpaper(path: "/a/1.jpg"),
            Wallpaper(path: "/a/sub/2.jpg"),
            Wallpaper(path: "/ab/3.jpg"),
        ])
        state.sources = [LibrarySource(kind: .folder, path: "/a")]
        #expect(state.wallpapers(in: state.sources[0]).map(\.path) == ["/a/1.jpg"])
        state.sources[0].includeSubfolders = true
        #expect(state.wallpapers(in: state.sources[0]).map(\.path) == ["/a/1.jpg", "/a/sub/2.jpg"])
    }

    @Test func resolvesMovedFolderThroughBookmark() throws {
        let dir = try TemporaryDirectory()
        let original = dir.url.appendingPathComponent("Walls")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        var state = LibraryState()
        state.addSource(at: original, isDirectory: true)

        let moved = dir.url.appendingPathComponent("Moved")
        try FileManager.default.moveItem(at: original, to: moved)

        let changed = state.resolveMovedSources()
        #expect(changed)
        #expect(state.sources[0].path == moved.path)
    }
}

@Suite(.serialized) struct DirectoryWatcherTests {
    /// Starts watching `dir`, performs `change`, and waits for the watcher to report it.
    private func expectChange(in dir: TemporaryDirectory, _ change: () throws -> Void) async throws -> Bool {
        let watcher = DirectoryWatcher(latency: 0.1)
        let (events, continuation) = AsyncStream<Void>.makeStream()
        watcher.watch(paths: [dir.url.path]) { continuation.yield() }
        defer { watcher.stop() }

        // Give FSEvents a moment to start before making the change.
        try await Task.sleep(for: .milliseconds(300))
        try change()

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in events { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            continuation.finish()
            return first
        }
    }

    @Test func reportsNewFile() async throws {
        let dir = try TemporaryDirectory()
        let fired = try await expectChange(in: dir) { try dir.makeFile("new.jpg") }
        #expect(fired)
    }

    @Test func reportsDeletedFile() async throws {
        let dir = try TemporaryDirectory()
        let file = try dir.makeFile("old.jpg")
        let fired = try await expectChange(in: dir) { try FileManager.default.removeItem(at: file) }
        #expect(fired)
    }
}
