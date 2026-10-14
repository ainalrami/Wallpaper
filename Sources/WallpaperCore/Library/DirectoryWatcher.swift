import CoreServices
import Foundation

/// Reports changes inside a set of folders.
public protocol FileSystemWatching: AnyObject, Sendable {
    /// Called on a background queue after changes, coalesced over a short interval.
    func watch(paths: [String], onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// Watches folders recursively with FSEvents.
public final class DirectoryWatcher: FileSystemWatching, @unchecked Sendable {
    private let latency: CFTimeInterval
    private let queue = DispatchQueue(label: "WallpaperManager.DirectoryWatcher")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var onChange: (@Sendable () -> Void)?

    /// - Parameter latency: how long FSEvents waits to coalesce events before reporting them.
    public init(latency: CFTimeInterval = 0.3) {
        self.latency = latency
    }

    deinit {
        stop()
    }

    public func watch(paths: [String], onChange: @escaping @Sendable () -> Void) {
        stop()
        guard !paths.isEmpty else { return }

        lock.withLock { self.onChange = onChange }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.lock.withLock { watcher.onChange }?()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        lock.withLock { self.stream = stream }
    }

    public func stop() {
        let stream: FSEventStreamRef? = lock.withLock {
            defer { self.stream = nil; self.onChange = nil }
            return self.stream
        }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
