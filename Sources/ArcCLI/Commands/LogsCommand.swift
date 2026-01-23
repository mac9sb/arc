import ArcCore
import ArgumentParser
import Foundation
import Noora
import PklSwift

/// Thread-safe box for passing errors from async Tasks
private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

/// Command to view Arc server logs.
///
/// Displays log file contents, with optional follow mode for real-time
/// log streaming.
///
/// ## Usage
///
/// ```sh
/// arc logs                # Show last 50 lines of logs
/// arc logs --follow       # Follow log output (like tail -f)
/// ```
public struct LogsCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Show arc server logs"
    )

    /// Path to the Pkl configuration file.
    ///
    /// Defaults to `config.pkl` in the current directory.
    @Option(name: .shortAndLong, help: "Path to config file")
    var config: String = "config.pkl"

    /// Whether to follow log output in real-time.
    ///
    /// When enabled, continuously displays new log entries as they are written,
    /// similar to `tail -f`.
    @Flag(name: .long, help: "Follow log output")
    var follow: Bool = false

    /// Executes the logs command.
    ///
    /// Reads and displays log file contents. In follow mode, streams new
    /// log entries as they are written.
    ///
    /// - Throws: An error if the log file cannot be read.
    public func run() throws {
        let configPath = config
        let shouldFollow = follow

        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()

        Task { @Sendable in
            defer { semaphore.signal() }
            do {
                try await Self.runAsync(configPath: configPath, follow: shouldFollow)
            } catch {
                errorBox.error = error
            }
        }

        semaphore.wait()
        if let error = errorBox.error {
            throw error
        }
    }

    private static func runAsync(configPath: String, follow: Bool) async throws {
        // Resolve relative paths to absolute paths
        // First expand tilde paths
        let expandedPath = (configPath as NSString).expandingTildeInPath
        let resolvedPath: String
        if (expandedPath as NSString).isAbsolutePath {
            resolvedPath = expandedPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
        }

        let configURL = URL(fileURLWithPath: resolvedPath)

        guard
            let config = try? await ArcConfig.loadFrom(
                source: ModuleSource.path(resolvedPath),
                configPath: configURL
            )
        else {
            Noora().warning("Could not load configuration: invalid config file")
            return
        }

        let logPath = "\((config.logDir as NSString).expandingTildeInPath)/arc.log"

        if !FileManager.default.fileExists(atPath: logPath) {
            Noora().warning("Log file not found")
            return
        }

        if follow {
            let tailProcess = Process()
            tailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
            tailProcess.arguments = ["-f", logPath]
            tailProcess.standardOutput = FileHandle.standardOutput
            tailProcess.standardError = FileHandle.standardError
            try tailProcess.run()
            tailProcess.waitUntilExit()
        } else {
            let content = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let lastLines = Array(lines.suffix(50))

            Noora().info("Log file: \(logPath)")
            print(lastLines.joined(separator: "\n"))
        }
    }
}
