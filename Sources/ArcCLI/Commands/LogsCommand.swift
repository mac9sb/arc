import ArcCore
import ArgumentParser
import Foundation
import Noora

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
        let configPath = "Arc.swift"
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

        // Find all log files: arc server + all managed processes
        let baseDir = config.baseDir ?? configURL.deletingLastPathComponent().path
        let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
        let manager = ProcessDescriptorManager(baseDir: pidDir)
        let logDir = (config.logDir as NSString).expandingTildeInPath

        var logPaths: [String] = []

        // Add arc server log
        let descriptors = (try? await manager.listAll()) ?? []
        let activeDescriptor = descriptors.first { descriptor in
            ServiceDetector.isProcessRunning(pid: descriptor.pid)
        }
        if let descriptor = activeDescriptor {
            let arcLogPath = "\(logDir)/\(descriptor.name).log"
            if FileManager.default.fileExists(atPath: arcLogPath) {
                logPaths.append(arcLogPath)
            }
        }

        // Add logs for all managed app processes
        for site in config.sites {
            switch site {
            case .app:
                let siteLogPath = "\(logDir)/\(site.name).log"
                if FileManager.default.fileExists(atPath: siteLogPath) {
                    logPaths.append(siteLogPath)
                }
            case .static:
                // Static sites don't have separate process logs, but requests are logged to arc server log
                break
            }
        }

        if logPaths.isEmpty {
            Noora().warning("No log files found in \(logDir)")
            return
        }

        if follow {
            // Use tail -f on all log files
            let tailProcess = Process()
            tailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
            tailProcess.arguments = ["-f"] + logPaths
            tailProcess.standardOutput = FileHandle.standardOutput
            tailProcess.standardError = FileHandle.standardError
            try tailProcess.run()
            tailProcess.waitUntilExit()
        } else {
            // Merge and show last 50 lines from all logs
            var allLines: [(path: String, line: String, timestamp: Date?)] = []

            for logPath in logPaths {
                if let content = try? String(contentsOfFile: logPath, encoding: .utf8) {
                    let lines = content.components(separatedBy: "\n")
                    for line in lines {
                        if !line.isEmpty {
                            // Try to extract timestamp from log line (ISO8601 format)
                            let timestamp = extractTimestamp(from: line)
                            allLines.append((path: logPath, line: line, timestamp: timestamp))
                        }
                    }
                }
            }

            // Sort by timestamp if available, otherwise by file order
            allLines.sort { line1, line2 in
                if let ts1 = line1.timestamp, let ts2 = line2.timestamp {
                    return ts1 < ts2
                }
                return false  // Keep original order if no timestamps
            }

            let lastLines = Array(allLines.suffix(50))
            for (_, line, _) in lastLines {
                print(line)
            }
        }
    }

    /// Extracts timestamp from a log line (ISO8601 format).
    private static func extractTimestamp(from line: String) -> Date? {
        // Look for ISO8601 timestamp pattern: YYYY-MM-DDTHH:MM:SS
        let pattern = #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            let timestampString = String(line[range])
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: timestampString) {
                return date
            }
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: timestampString)
        }
        return nil
    }
}
