import ArcCore
import ArgumentParser
import Foundation
import Noora

/// Thread-safe box for passing errors from async Tasks
private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

/// Command to stop Arc server processes.
///
/// Stops running Arc servers gracefully, with fallback to force kill if needed.
/// Can stop a specific process by name, all processes, or interactively select
/// from a list.
///
/// ## Usage
///
/// ```sh
/// arc stop                # Interactive mode: list and select process
/// arc stop <name>         # Stop a specific process by name
/// arc stop --all          # Stop all running processes
/// ```
public struct StopCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop arc server"
    )



    /// Optional process name to stop.
    ///
    /// If provided, stops only the specified process. If omitted and `all` is
    /// false, enters interactive mode.
    @Argument(help: "Optional process name to stop")
    var name: String?

    /// Whether to stop all running Arc processes.
    ///
    /// When enabled, stops all running Arc server processes regardless of
    /// the `name` argument.
    @Flag(name: .long, help: "Stop all running arc processes")
    var all: Bool = false

    /// Executes the stop command.
    ///
    /// Stops processes gracefully using SIGTERM, with automatic fallback to
    /// SIGKILL if graceful shutdown fails.
    ///
    /// - Throws: An error if process stopping fails.
    public func run() throws {
        let configPath = "ArcManifest.swift"
        let processName = name
        let stopAll = all

        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()

        Task { @Sendable in
            defer { semaphore.signal() }
            do {
                // Expand tilde paths before creating URL
                let expandedPath = (configPath as NSString).expandingTildeInPath
                let resolvedPath: String
                if (expandedPath as NSString).isAbsolutePath {
                    resolvedPath = expandedPath
                } else {
                    let currentDir = FileManager.default.currentDirectoryPath
                    resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
                }
                let configURL = URL(fileURLWithPath: resolvedPath)
                let baseDir = configURL.deletingLastPathComponent().path
                let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")

                let manager = ProcessDescriptorManager(baseDir: pidDir)

                // Clean up stale descriptors first
                let removed = try await manager.cleanupStale()
                if !removed.isEmpty {
                    Noora().info("Cleaned up \(removed.count) stale process(es)")
                }

                let descriptors = try await manager.listAll()

                if stopAll {
                    try await Self.stopAllProcesses(descriptors: descriptors, manager: manager)
                } else if let processName = processName {
                    try await Self.stopProcess(named: processName, descriptors: descriptors, manager: manager)
                } else {
                    // Interactive mode
                    if descriptors.isEmpty {
                        Noora().warning("No running arc server processes found")
                        return
                    }

                    Noora().info("Running Arc Servers")
                    var rows: [[String]] = []
                    for descriptor in descriptors {
                        let uptime = Self.uptimeString(from: descriptor.startedAt)
                        let statusEmoji = ServiceDetector.isProcessRunning(pid: descriptor.pid) ? "🟢" : "🔴"
                        rows.append([
                            statusEmoji + " " + descriptor.name,
                            String(descriptor.pid),
                            String(descriptor.proxyPort),
                            uptime,
                        ])
                    }

                    print(String(format: "%-30s %-10s %-8s %s", "NAME", "PID", "PORT", "UPTIME"))
                    print(String(repeating: "-", count: 70))
                    for row in rows {
                        print(String(format: "%-30s %-10s %-8s %s", row[0], row[1], row[2], row[3]))
                    }

                    if descriptors.count == 1 {
                        let descriptor = descriptors[0]
                        Noora().info("Stopping only running process: \(descriptor.name)")
                        try await Self.stopProcess(descriptor: descriptor, manager: manager)
                    } else {
                        Noora().info("\nUse 'arc stop <name>' to stop a specific process")
                        Noora().info("Use 'arc stop --all' to stop all processes")
                    }
                }
            } catch {
                errorBox.error = error
            }
        }

        semaphore.wait()
        if let error = errorBox.error {
            throw error
        }
    }

    // MARK: - Stop All Processes

    private static func stopAllProcesses(
        descriptors: [ProcessDescriptor],
        manager: ProcessDescriptorManager
    ) async throws {
        if descriptors.isEmpty {
            Noora().info("No running arc server processes to stop")
            return
        }

        Noora().info("Stopping \(descriptors.count) arc process(es)...")

        for descriptor in descriptors {
            try await stopProcess(descriptor: descriptor, manager: manager)
        }

        Noora().success("All arc servers stopped")
    }

    // MARK: - Stop Process by Name

    private static func stopProcess(
        named processName: String,
        descriptors: [ProcessDescriptor],
        manager: ProcessDescriptorManager
    ) async throws {
        guard let descriptor = descriptors.first(where: { $0.name == processName }) else {
            Noora().error("Process '\(processName)' not found")
            Noora().info("Run 'arc status' to list running processes")
            return
        }

        try await stopProcess(descriptor: descriptor, manager: manager)
    }

    // MARK: - Stop Individual Process

    private static func stopProcess(
        descriptor: ProcessDescriptor,
        manager: ProcessDescriptorManager
    ) async throws {
        let isRunning = ServiceDetector.isProcessRunning(pid: descriptor.pid)

        if !isRunning {
            Noora().warning("Process '\(descriptor.name)' is not running (stale PID file)")
            try await manager.delete(name: descriptor.name)
            return
        }

        Noora().info("Stopping \(descriptor.name) (PID: \(descriptor.pid))...")

        // Try graceful shutdown first
        Noora().info("Sending SIGTERM...")
        let didSendTerm = ServiceDetector.killProcess(pid: descriptor.pid, signal: .term)
        if !didSendTerm {
            Noora().warning("Failed to send SIGTERM to process")
        }

        // Wait for graceful shutdown (up to 10 seconds)
        for i in 0..<100 {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

            if !ServiceDetector.isProcessRunning(pid: descriptor.pid) {
                Noora().success("Process stopped gracefully")
                try await manager.delete(name: descriptor.name)
                return
            }

            if i % 10 == 0 {  // Every second
                Noora().info("Waiting for process to stop...")
            }
        }

        // Force kill if graceful shutdown failed
        Noora().warning("Process did not stop gracefully, sending SIGKILL...")
        let didSendKill = ServiceDetector.killProcess(pid: descriptor.pid, signal: .kill)
        if !didSendKill {
            Noora().warning("Failed to send SIGKILL to process")
        }

        try await Task.sleep(nanoseconds: 500_000_000)  // Wait 500ms for cleanup

        let stillRunning = ServiceDetector.isProcessRunning(pid: descriptor.pid)
        if stillRunning {
            Noora().error("Failed to stop process \(descriptor.name)")
        } else {
            Noora().success("Process stopped")
        }

        try await manager.delete(name: descriptor.name)
    }

    // MARK: - Helpers

    private static func uptimeString(from startDate: Date) -> String {
        let elapsed = Date().timeIntervalSince(startDate)
        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3600)) / 60
        let seconds = Int(elapsed.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
