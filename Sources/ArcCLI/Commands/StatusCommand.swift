import ArcCore
import ArcServer
import ArgumentParser
import Foundation
import Noora
import PklSwift

/// Command to display the status of Arc server processes.
///
/// Shows information about running Arc processes, including:
/// - Process name, PID, and port
/// - CPU and memory usage
/// - Uptime
/// - Site health status
///
/// ## Usage
///
/// ```bash
/// arc status              # List all running processes
/// arc status <name>        # Show detailed status for a specific process
/// ```
struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show arc server status"
    )

    /// Path to the Pkl configuration file.
    ///
    /// Defaults to `pkl/config.pkl` in the current directory.
    @Option(name: .shortAndLong, help: "Path to config file")
    var config: String = "pkl/config.pkl"

    /// Optional process name to inspect.
    ///
    /// If provided, shows detailed status for the specified process including
    /// site health information. If omitted, lists all running processes.
    @Argument(help: "Optional process name to inspect")
    var name: String?

    /// Executes the status command.
    ///
    /// Displays process information either for all processes or a specific
    /// process if a name is provided.
    ///
    /// - Throws: An error if configuration loading or process inspection fails.
    func run() async throws {
        let configURL = URL(fileURLWithPath: config)
        let baseDir = configURL.deletingLastPathComponent().path
        let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")

        let manager = ProcessDescriptorManager(baseDir: pidDir)

        if let processName = name {
            // Show per-process site view
            try await showProcessDetails(
                processName: processName, manager: manager, baseDir: baseDir)
        } else {
            // List all processes
            try await listAllProcesses(manager: manager)
        }
    }

    // MARK: - List All Processes

    private func listAllProcesses(manager: ProcessDescriptorManager) async throws {
        let descriptors = try await manager.listAll()

        if descriptors.isEmpty {
            Noora().info("No arc server processes found")
            return
        }

        // Clean up stale descriptors
        let removed = try await manager.cleanupStale()
        if !removed.isEmpty {
            Noora().info("Cleaned up \(removed.count) stale process(es)")
        }

        // Refresh descriptors after cleanup
        let activeDescriptors = try await manager.listAll()

        if activeDescriptors.isEmpty {
            Noora().info("No running arc server processes")
            return
        }

        Noora().info("Arc Server Processes")

        var rows: [[String]] = []
        for descriptor in activeDescriptors {
            let usage = await manager.getResourceUsage(pid: descriptor.pid)
            let cpuPercent = usage?.cpuPercent ?? 0.0
            let memoryMB = usage?.memoryMB ?? 0.0
            let uptime = uptimeString(from: descriptor.startedAt)

            let statusEmoji = ServiceDetector.isProcessRunning(pid: descriptor.pid) ? "🟢" : "🔴"

            rows.append([
                statusEmoji + " " + descriptor.name,
                String(descriptor.pid),
                String(descriptor.proxyPort),
                String(format: "%.1f%%", cpuPercent),
                String(format: "%.1f MB", memoryMB),
                uptime,
            ])
        }

        // Simple table output
        print(
            String(
                format: "%-35s %-10s %-8s %-10s %-12s %s", "NAME", "PID", "PORT", "CPU", "RAM",
                "UPTIME"))
        print(String(repeating: "-", count: 100))
        for row in rows {
            print(
                String(
                    format: "%-35s %-10s %-8s %-10s %-12s %s", row[0], row[1], row[2], row[3],
                    row[4], row[5]))
        }
    }

    // MARK: - Show Process Details

    private func showProcessDetails(
        processName: String,
        manager: ProcessDescriptorManager,
        baseDir: String
    ) async throws {
        guard let descriptor = try await manager.read(name: processName) else {
            Noora().error("Process '\(processName)' not found")
            return
        }

        // Check if process is running
        let isRunning = ServiceDetector.isProcessRunning(pid: descriptor.pid)
        if !isRunning {
            Noora().warning("Process '\(processName)' is not running (stale PID file)")
            return
        }

        // Load config
        let configURL = URL(fileURLWithPath: descriptor.configPath)
        guard
            let config = try? await ArcConfig.loadFrom(
                source: ModuleSource.path(descriptor.configPath),
                configPath: configURL
            )
        else {
            Noora().error("Failed to load configuration from \(descriptor.configPath)")
            return
        }

        // Show process info
        let usage = await manager.getResourceUsage(pid: descriptor.pid)
        Noora().info("Process: \(descriptor.name)")
        Noora().info("  PID: \(descriptor.pid)")
        Noora().info("  Proxy Port: \(descriptor.proxyPort)")
        Noora().info("  Config: \(descriptor.configPath)")
        Noora().info("  Started: \(formatDate(descriptor.startedAt))")
        Noora().info("  Uptime: \(uptimeString(from: descriptor.startedAt))")

        if let usage = usage {
            Noora().info("  CPU: \(String(format: "%.1f%%", usage.cpuPercent))")
            Noora().info("  Memory: \(String(format: "%.1f MB", usage.memoryMB))")
            Noora().info("  Command: \(usage.command)")
        }

        // Show sites table
        Noora().info("Sites")

        var rows: [[String]] = []
        for site in config.sites {
            let kind: String
            let health: String
            let port: String
            let cpu: String
            let ram: String

            switch site {
            case .static(let staticSite):
                kind = "static"
                let outputPath = resolvePath(
                    staticSite.outputPath,
                    baseDir: config.baseDir,
                    workingDir: nil
                )
                let exists = FileManager.default.fileExists(atPath: outputPath)
                health = exists ? "✅" : "⚠️"
                port = "-"
                cpu = "-"
                ram = "-"

            case .app(let appSite):
                kind = "app"
                port = String(appSite.port)

                // Check health using ProxyHandler
                let proxyHandler = ProxyHandler(config: config)
                let healthCheck = await proxyHandler.checkHealth(appSite: appSite)
                health = healthCheck.ok ? "✅" : "❌"

                // Use parent process CPU/RAM (child processes not tracked yet)
                if let usage = await manager.getResourceUsage(pid: descriptor.pid) {
                    cpu = String(format: "%.1f%%", usage.cpuPercent)
                    ram = String(format: "%.1f MB", usage.memoryMB)
                } else {
                    cpu = "-"
                    ram = "-"
                }
            }

            rows.append([site.name, site.domain, kind, health, port, cpu, ram])
        }

        // Simple table output
        print(
            String(
                format: "%-25s %-30s %-10s %-8s %-8s %-10s %s", "SITE", "DOMAIN", "KIND", "HEALTH",
                "PORT", "CPU", "RAM"))
        print(String(repeating: "-", count: 100))
        for row in rows {
            print(
                String(
                    format: "%-25s %-30s %-10s %-8s %-8s %-10s %s", row[0], row[1], row[2], row[3],
                    row[4], row[5], row[6]))
        }

        // Show log file location
        let logPath = "\(config.logDir)/\(descriptor.name).log"
        Noora().info("\nLogs: \(logPath)")
        Noora().info("View logs with: arc logs --config \(descriptor.configPath)")
    }

    // MARK: - Helpers

    private func resolvePath(_ path: String, baseDir: String?, workingDir: String?) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return expanded
        }

        if let workingDir {
            let candidate = (workingDir as NSString).appendingPathComponent(expanded)
            if (candidate as NSString).isAbsolutePath { return candidate }
            if let baseDir {
                return (baseDir as NSString).appendingPathComponent(candidate)
            }
            return candidate
        }

        if let baseDir {
            return (baseDir as NSString).appendingPathComponent(expanded)
        }
        return expanded
    }

    private func uptimeString(from startDate: Date) -> String {
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
