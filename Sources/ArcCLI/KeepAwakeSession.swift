import Foundation
import Noora

final class KeepAwakeSession {
    private static let caffeinatePath = "/usr/bin/caffeinate"

    private let process: Process

    private init(process: Process) {
        self.process = process
    }

    static func startIfNeeded(enabled: Bool, verbose: Bool) -> KeepAwakeSession? {
        guard enabled else { return nil }

        guard FileManager.default.isExecutableFile(atPath: caffeinatePath) else {
            Noora().warning("Keep-awake requested, but caffeinate is unavailable.")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: caffeinatePath)
        process.arguments = ["-dimsu"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Noora().warning("Failed to start keep-awake: \(error.localizedDescription)")
            return nil
        }

        if verbose {
            Noora().info("Keep-awake enabled")
        }

        return KeepAwakeSession(process: process)
    }

    func stop(verbose: Bool) {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
        if verbose {
            Noora().info("Keep-awake disabled")
        }
    }
}
