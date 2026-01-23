import Foundation
import Testing

@testable import ArcCore

@Suite("ServiceDetector Tests")
struct ServiceDetectorTests {
    @Test("IsProcessRunning returns false for invalid PID")
    func testIsProcessRunningInvalidPID() {
        let invalidPID: Int32 = -1
        #expect(!ServiceDetector.isProcessRunning(pid: invalidPID))
    }

    @Test("IsProcessRunning returns true for current process")
    func testIsProcessRunningCurrentProcess() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        #expect(ServiceDetector.isProcessRunning(pid: Int32(currentPID)))
    }

    @Test("KillProcess sends signal to process")
    func testKillProcess() {
        // Test with current process (should succeed but not actually kill)
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // SIGTERM should succeed (process exists)
        let termResult = ServiceDetector.killProcess(pid: Int32(currentPID), signal: .term)
        #expect(termResult)

        // Process should still be running
        #expect(ServiceDetector.isProcessRunning(pid: Int32(currentPID)))
    }
}
