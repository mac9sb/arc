import Dispatch
import Foundation
#if os(Linux)
import Glibc
#endif

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

    private let targets: [WatchTarget]
    private let debounceConfig: DebounceConfig
    private let followSymlinks: Bool
    private let queue = DispatchQueue(label: "com.arc.filewatcher")
    #if os(macOS)
    private var dispatchSources: [DispatchSourceFileSystemObject] = []
    #elseif os(Linux)
    private var inotifyFD: Int32 = -1
    private var watchDescriptors: [String: Int32] = [:]
    private var inotifySource: DispatchSourceRead?
    #endif
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
            #if os(macOS)
            self?.setupWatchers()
            #elseif os(Linux)
            self?.setupWatchersLinux()
            #endif
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

    #if os(macOS)
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
    #elseif os(Linux)
    private func setupWatchersLinux() {
        // Initialize inotify
        inotifyFD = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard inotifyFD >= 0 else {
            return
        }
        
        // Create a dispatch source for reading inotify events
        let source = DispatchSource.makeReadSource(fileDescriptor: inotifyFD, queue: queue)
        
        source.setEventHandler { [weak self] in
            self?.handleInotifyEvents()
        }
        
        source.setCancelHandler { [weak self] in
            if let fd = self?.inotifyFD, fd >= 0 {
                Glibc.close(fd)
            }
        }
        
        source.resume()
        inotifySource = source
        
        // Setup watchers for each target
        for target in targets {
            setupWatcherLinux(for: target)
        }
    }
    
    private func setupWatcherLinux(for target: WatchTarget) {
        // Expand tilde and resolve path
        let path = target.path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            // File doesn't exist yet - watch parent directory
            setupParentDirectoryWatcherLinux(for: path, target: target)
            return
        }
        
        if !followSymlinks {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            if let fileType = attrs?[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
                // Don't follow symlinks by default
                return
            }
        }
        
        // Add inotify watch
        let watchMask: UInt32 = UInt32(IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE | IN_DELETE_SELF)
        let wd = path.withCString { cString in
            inotify_add_watch(inotifyFD, cString, watchMask)
        }
        
        guard wd >= 0 else {
            return
        }
        
        watchDescriptors[path] = wd
    }
    
    private func setupParentDirectoryWatcherLinux(for path: String, target: WatchTarget) {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        
        let watchMask: UInt32 = UInt32(IN_CREATE | IN_MOVED_TO | IN_MODIFY)
        let wd = parent.withCString { cString in
            inotify_add_watch(inotifyFD, cString, watchMask)
        }
        
        guard wd >= 0 else {
            return
        }
        
        watchDescriptors[parent] = wd
    }
    
    private func handleInotifyEvents() {
        // Use aligned buffer for inotify events
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        while true {
            let length = Glibc.read(inotifyFD, &buffer, bufferSize)
            if length <= 0 {
                break
            }
            
            var offset = 0
            while offset < length {
                // Read the fixed-size part of the event
                let eventBase = buffer.withUnsafeBytes { bytes -> inotify_event in
                    let ptr = bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: inotify_event.self)
                    return ptr.pointee
                }
                
                // Calculate total event size (fixed size + variable length name)
                let eventSize = MemoryLayout<inotify_event>.size + Int(eventBase.len)
                
                // Find which target this event corresponds to
                if let target = findTargetForWatchDescriptor(Int32(eventBase.wd)) {
                    // Check if this is a relevant event
                    let relevantMask = UInt32(IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE | IN_DELETE_SELF | IN_CREATE)
                    if (eventBase.mask & relevantMask) != 0 {
                        handleEvent(for: target)
                    }
                }
                
                offset += eventSize
            }
        }
    }
    
    private func findTargetForWatchDescriptor(_ wd: Int32) -> WatchTarget? {
        // Find target by matching watch descriptor to path
        for (path, storedWd) in watchDescriptors {
            if storedWd == wd {
                // Try exact match first
                if let exact = targets.first(where: { 
                    let expanded = $0.path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
                    return expanded == path 
                }) {
                    return exact
                }
                // Try parent directory match
                return targets.first { targetPath in
                    let expanded = targetPath.path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
                    let targetParent = URL(fileURLWithPath: expanded).deletingLastPathComponent().path
                    return targetParent == path
                }
            }
        }
        return nil
    }
    #endif

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

        #if os(macOS)
        dispatchSources.forEach { $0.cancel() }
        dispatchSources.removeAll()
        #elseif os(Linux)
        // Remove all inotify watches
        for (_, wd) in watchDescriptors {
            inotify_rm_watch(inotifyFD, UInt32(wd))
        }
        watchDescriptors.removeAll()
        
        inotifySource?.cancel()
        inotifySource = nil
        
        if inotifyFD >= 0 {
            Glibc.close(inotifyFD)
            inotifyFD = -1
        }
        #endif

        lastTriggerTime.removeAll()
    }

    deinit {
        cleanup()
    }
}

#if os(Linux)
// inotify constants
private let IN_ACCESS: UInt32 = 0x00000001
private let IN_MODIFY: UInt32 = 0x00000002
private let IN_ATTRIB: UInt32 = 0x00000004
private let IN_CLOSE_WRITE: UInt32 = 0x00000008
private let IN_CLOSE_NOWRITE: UInt32 = 0x00000010
private let IN_OPEN: UInt32 = 0x00000020
private let IN_MOVED_FROM: UInt32 = 0x00000040
private let IN_MOVED_TO: UInt32 = 0x00000080
private let IN_CREATE: UInt32 = 0x00000100
private let IN_DELETE: UInt32 = 0x00000200
private let IN_DELETE_SELF: UInt32 = 0x00000400
private let IN_MOVE_SELF: UInt32 = 0x00000800
private let IN_NONBLOCK: Int32 = 0x00004000
private let IN_CLOEXEC: Int32 = 0x02000000

// C-compatible inotify_event structure
// Note: The 'name' field is a flexible array member in C, which Swift doesn't support directly
// We only read the fixed-size fields and handle the variable-length name separately
private struct inotify_event {
    var wd: Int32      // Watch descriptor
    var mask: UInt32   // Event mask
    var cookie: UInt32 // Cookie for rename events
    var len: UInt32    // Length of name field (including null terminator)
    // name[0] follows in C (flexible array member - not represented here)
}

@_silgen_name("inotify_init1")
private func inotify_init1(_ flags: Int32) -> Int32

@_silgen_name("inotify_add_watch")
private func inotify_add_watch(_ fd: Int32, _ pathname: UnsafePointer<CChar>, _ mask: UInt32) -> Int32

@_silgen_name("inotify_rm_watch")
private func inotify_rm_watch(_ fd: Int32, _ wd: UInt32) -> Int32
#endif
