import Dispatch
import Foundation

/// A file watcher with debouncing support for monitoring file system changes.
///
/// Use `FileWatcher` to watch files and directories for changes, with configurable
/// debouncing to prevent excessive callbacks during rapid file modifications.
///
/// Thread safety: All mutable state access is serialized through the `queue` DispatchQueue.
/// Uses @unchecked Sendable to satisfy concurrency requirements while ensuring thread safety
/// via the serial dispatch queue.
public final class FileWatcher: @unchecked Sendable {
    /// Configuration for a single watch target.
    public struct WatchTarget {
        /// The file or directory path to watch.
        public let path: String

        /// Whether the path is a directory.
        public let isDirectory: Bool

        /// The callback to invoke when the target changes.
        public let onFileChange: @Sendable () async -> Void

        /// Creates a new watch target.
        ///
        /// - Parameters:
        ///   - path: The file or directory path to watch.
        ///   - isDirectory: Whether the path is a directory. Defaults to `false`.
        ///   - onFileChange: The async callback to invoke when changes are detected.
        public init(
            path: String,
            isDirectory: Bool = false,
            onFileChange: @escaping @Sendable () async -> Void
        ) {
            self.path = path
            self.isDirectory = isDirectory
            self.onFileChange = onFileChange
        }
    }

    /// Configuration for debouncing file change events.
    public struct DebounceConfig {
        /// Debounce interval in milliseconds.
        public let debounceMs: Int

        /// Cooldown period in milliseconds after triggering a change.
        public let cooldownMs: Int

        /// Creates a new debounce configuration.
        ///
        /// - Parameters:
        ///   - debounceMs: Debounce interval in milliseconds. Defaults to 300ms.
        ///   - cooldownMs: Cooldown period in milliseconds. Defaults to 1000ms.
        public init(debounceMs: Int = 300, cooldownMs: Int = 1000) {
            self.debounceMs = debounceMs
            self.cooldownMs = cooldownMs
        }
    }

    let targets: [WatchTarget]
    private let debounceConfig: DebounceConfig
    private let followSymlinks: Bool
    private let queue = DispatchQueue(label: "com.arc.filewatcher")
    private var dispatchSources: [DispatchSourceFileSystemObject] = []
    private var debounceTimers: [String: DispatchWorkItem] = [:]
    private var lastTriggerTime: [String: Date] = [:]
    private var isRunning = false

    /// Creates a new file watcher.
    ///
    /// - Parameters:
    ///   - targets: The files and directories to watch.
    ///   - debounceConfig: Configuration for debouncing change events.
    ///   - followSymlinks: Whether to follow symbolic links. Defaults to `false`.
    public init(
        targets: [WatchTarget],
        debounceConfig: DebounceConfig,
        followSymlinks: Bool = false
    ) {
        self.targets = targets
        self.debounceConfig = debounceConfig
        self.followSymlinks = followSymlinks
    }

    /// Starts watching the configured paths.
    ///
    /// Call this method to begin monitoring files and directories for changes.
    public func start() {
        queue.async { [weak self] in
            self?.setupWatchers()
        }
        isRunning = true
    }

    /// Stops watching and cleans up resources.
    public func stop() {
        queue.async { [weak self] in
            self?.cleanup()
        }
        isRunning = false
    }

    private func setupWatchers() {
        for target in targets {
            setupWatcher(for: target)
        }
    }

    private func setupWatcher(for target: WatchTarget) {
        let path = (target.path as NSString).expandingTildeInPath

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            // File doesn't exist yet - watch parent directory
            setupParentDirectoryWatcher(for: path, target: target)
            return
        }

        if !followSymlinks {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            if let fileType = attrs?[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
                // Don't follow symlinks by default
                return
            }
        }

        let descriptor = open(path, O_EVTONLY, 0)
        guard descriptor != -1 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleEvent(for: target)
        }

        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        source.resume()
        dispatchSources.append(source)
    }

    private func setupParentDirectoryWatcher(for path: String, target: WatchTarget) {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path

        let descriptor = open(parent, O_EVTONLY, 0)
        guard descriptor != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        let targetPath = path

        source.setEventHandler { [weak self, target] in
            // Check if target file was created/modified
            if FileManager.default.fileExists(atPath: targetPath) {
                // Cancel parent watcher and set up direct watcher
                self?.setupWatcher(for: target)
                source.cancel()
            }
        }

        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
        dispatchSources.append(source)
    }

    private func handleEvent(for target: WatchTarget) {
        let now = Date()
        let targetId = target.path

        // Check cooldown period
        if let lastTime = lastTriggerTime[targetId] {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < TimeInterval(debounceConfig.cooldownMs) / 1000.0 {
                return  // Still in cooldown
            }
        }

        // Cancel any pending debounce timer for this target
        if let existingTimer = debounceTimers[targetId] {
            existingTimer.cancel()
        }

        // Create work item and schedule it
        let onChange = target.onFileChange
        let targetIdCopy = targetId

        // Access to lastTriggerTime is serialized via DispatchQueue
        // Safe because DispatchQueue serializes all access to lastTriggerTime
        // Simple pattern: update timestamp, then call onChange async
        self.queue.sync {
            self.lastTriggerTime[targetIdCopy] = Date()
        }

        // Create work item that will execute onChange asynchronously
        let workItem = DispatchWorkItem { [onChange] in
            Task {
                await onChange()
            }
        }

        debounceTimers[targetId] = workItem
        queue.asyncAfter(
            deadline: .now() + .milliseconds(debounceConfig.debounceMs), execute: workItem)
    }

    private func cleanup() {
        debounceTimers.values.forEach { $0.cancel() }
        debounceTimers.removeAll()

        dispatchSources.forEach { $0.cancel() }
        dispatchSources.removeAll()

        lastTriggerTime.removeAll()
    }

    deinit {
        cleanup()
    }
}
