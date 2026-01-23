import Foundation
import Testing

@testable import ArcCore

@Suite("FileWatcher Tests")
struct FileWatcherTests {
    @Test("FileWatcher initializes with targets")
    func testFileWatcherInitializes() {
        let target = FileWatcher.WatchTarget(
            path: "/tmp/test",
            isDirectory: false,
            onFileChange: {}
        )

        let watcher = FileWatcher(
            targets: [target],
            debounceConfig: FileWatcher.DebounceConfig()
        )

        // FileWatcher is not optional, so just verify it was created
        #expect(watcher.targets.count == 1)
    }

    @Test("DebounceConfig has defaults")
    func testDebounceConfigDefaults() {
        let config = FileWatcher.DebounceConfig()
        #expect(config.debounceMs == 300)
        #expect(config.cooldownMs == 1000)
    }

    @Test("DebounceConfig accepts custom values")
    func testDebounceConfigCustom() {
        let config = FileWatcher.DebounceConfig(debounceMs: 500, cooldownMs: 2000)
        #expect(config.debounceMs == 500)
        #expect(config.cooldownMs == 2000)
    }
}
