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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        try? process.run()

        let pid = Int32(process.processIdentifier)
        #expect(ServiceDetector.isProcessRunning(pid: pid))

        let termResult = ServiceDetector.killProcess(pid: pid, signal: .term)
        #expect(termResult)

        process.waitUntilExit()
        #expect(!ServiceDetector.isProcessRunning(pid: pid))
    }
}
