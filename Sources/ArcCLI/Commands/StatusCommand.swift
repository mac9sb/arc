import ArcCore
import ArcServer
import ArgumentParser
import Foundation
import Noora
import PklSwift

/// Thread-safe box for passing errors from async Tasks
private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

/// Global flag for status command exit (must be accessible from C function pointers)
private final class StatusExitFlag {
    nonisolated(unsafe) static var value: Int32 = 0
}

/// Signal handler function for status command (must be a C function, cannot capture context)
private func statusExitSignalHandler(_ signal: Int32) {
    StatusExitFlag.value = 1
}

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
/// ```sh
/// arc status              # List all running processes
/// arc status <name>        # Show detailed status for a specific process
/// ```
public struct StatusCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show arc server status"
    )

    /// Path to the Pkl configuration file.
    ///
    /// Defaults to `config.pkl` in the current directory.
    @Option(name: .shortAndLong, help: "Path to config file")
    var config: String = "config.pkl"

    /// Optional process name to inspect.
    ///
    /// If provided, shows detailed status for the specified process including
    /// site health information. If omitted, lists all running processes.
    @Argument(help: "Optional process name to inspect")
    var name: String?

    /// Enable verbose logging output for debugging.
    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false

    /// Executes the status command.
    ///
    /// Displays process information either for all processes or a specific
    /// process if a name is provided.
    ///
    /// - Throws: An error if configuration loading or process inspection fails.
    public func run() throws {
        let configPath = config
        let processName = name
        let isVerbose = verbose

        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()

        Task { @Sendable in
            defer { semaphore.signal() }
            do {
                if isVerbose {
                    Noora().info("Verbose mode enabled")
                    Noora().info("Config path: \(configPath)")
                    if let processName = processName {
                        Noora().info("Process name: \(processName)")
                    }
                }
                // Expand tilde paths before creating URL
                let expandedPath = (configPath as NSString).expandingTildeInPath
                let resolvedPath: String
                if (expandedPath as NSString).isAbsolutePath {
                    resolvedPath = expandedPath
                } else {
                    let currentDir = FileManager.default.currentDirectoryPath
                    resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
                }
                
                // Load config to get baseDir (same logic as StartCommand)
                let configURL = URL(fileURLWithPath: resolvedPath)
                guard let config = try? await ArcConfig.loadFrom(
                    source: ModuleSource.path(resolvedPath),
                    configPath: configURL
                ) else {
                    // Fallback to config file directory if config can't be loaded
                    let baseDir = configURL.deletingLastPathComponent().path
                    let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
                    let manager = ProcessDescriptorManager(baseDir: pidDir)
                    
                    if let processName = processName {
                        try await Self.showProcessDetails(
                            processName: processName, manager: manager, baseDir: baseDir, verbose: isVerbose)
                    } else {
                        try await Self.listAllProcesses(manager: manager, verbose: isVerbose)
                    }
                    return
                }
                
                // Use same baseDir resolution as StartCommand
                let baseDir = config.baseDir ?? configURL.deletingLastPathComponent().path
                let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
                
                if isVerbose {
                    Noora().info("Base directory: \(baseDir)")
                    Noora().info("PID directory: \(pidDir.path)")
                }

                let manager = ProcessDescriptorManager(baseDir: pidDir)

                if let processName = processName {
                    try await Self.showProcessDetails(
                        processName: processName, manager: manager, baseDir: baseDir, verbose: isVerbose)
                } else {
                    try await Self.listAllProcesses(manager: manager, verbose: isVerbose)
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

    // MARK: - List All Processes

    private static func listAllProcesses(manager: ProcessDescriptorManager, verbose: Bool) async throws {
        // Set up signal handler for Ctrl+C
        StatusExitFlag.value = 0
        signal(SIGINT, statusExitSignalHandler)
        
        // Function to build table data
        func buildTableData() async -> TableData {
            // Clean up stale descriptors first
            _ = try? await manager.cleanupStale()
            
            // Get active descriptors
            let activeDescriptors = (try? await manager.listAll()) ?? []
            
            if activeDescriptors.isEmpty {
                // Return empty table
                let columns = [
                    TableColumn(title: "NAME", width: .auto, alignment: .left),
                    TableColumn(title: "PID", width: .auto, alignment: .right),
                    TableColumn(title: "PORT", width: .auto, alignment: .right),
                    TableColumn(title: "CPU", width: .auto, alignment: .right),
                    TableColumn(title: "RAM", width: .auto, alignment: .right),
                    TableColumn(title: "UPTIME", width: .auto, alignment: .left)
                ]
                return TableData(columns: columns, rows: [])
            }
            
            var rows: [[String]] = []
            for descriptor in activeDescriptors {
                // Check if process is running before trying to get resource usage
                let isRunning = ServiceDetector.isProcessRunning(pid: descriptor.pid)
                let statusEmoji = isRunning ? "🟢" : "🔴"
                
                // Only try to get resource usage if process is running
                let usage: ProcessResourceUsage?
                if isRunning {
                    usage = manager.getResourceUsage(pid: descriptor.pid)
                } else {
                    usage = nil
                }
                
                let cpuPercent = usage?.cpuPercent ?? 0.0
                let memoryMB = usage?.memoryMB ?? 0.0
                let uptime = uptimeString(from: descriptor.startedAt)

                rows.append([
                    statusEmoji + " " + descriptor.name,
                    String(descriptor.pid),
                    String(descriptor.proxyPort),
                    String(format: "%.1f%%", cpuPercent),
                    String(format: "%.1f MB", memoryMB),
                    uptime,
                ])
            }
            
            let columns = [
                TableColumn(title: "NAME", width: .auto, alignment: .left),
                TableColumn(title: "PID", width: .auto, alignment: .right),
                TableColumn(title: "PORT", width: .auto, alignment: .right),
                TableColumn(title: "CPU", width: .auto, alignment: .right),
                TableColumn(title: "RAM", width: .auto, alignment: .right),
                TableColumn(title: "UPTIME", width: .auto, alignment: .left)
            ]
            
            let tableRows = rows.map { row in
                row.map(TerminalText.init)
            }
            
            return TableData(columns: columns, rows: tableRows)
        }
        
        // Create initial table data
        let initialData = await buildTableData()
        
        // Create async stream for updates
        let updates = AsyncStream<TableData> { continuation in
            Task.detached {
                while StatusExitFlag.value == 0 && !Task.isCancelled {
                    let tableData = await buildTableData()
                    continuation.yield(tableData)
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Update every second
                }
                continuation.finish()
            }
        }
        
        // Display live updating table
        await Noora().table(initialData, updates: updates)
    }

    // MARK: - Show Process Details

    private static func showProcessDetails(
        processName: String,
        manager: ProcessDescriptorManager,
        baseDir: String,
        verbose: Bool
    ) async throws {
        guard let descriptor = try await manager.read(name: processName) else {
            Noora().error("Process '\(processName)' not found")
            return
        }

        // Check if process is running
        let isRunning = ServiceDetector.isProcessRunning(pid: descriptor.pid)
        if !isRunning {
            Noora().error("Process '\(processName)' is not running (stale PID file)")
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

        // Set up signal handler for Ctrl+C
        StatusExitFlag.value = 0
        signal(SIGINT, statusExitSignalHandler)
        
        // Function to build table data
        func buildTableData() async -> TableData {
            var processRows: [[String]] = []
            
            // Check if process is still running
            let isRunning = ServiceDetector.isProcessRunning(pid: descriptor.pid)
            let usage = isRunning ? manager.getResourceUsage(pid: descriptor.pid) : nil
            
            // Main arc process
            let mainCpu = usage?.cpuPercent ?? 0.0
            let mainRam = usage?.memoryMB ?? 0.0
            let mainStatus = isRunning ? "🟢" : "🔴"
            let sshStatus = (config.ssh?.enabled ?? false) ? "✅" : "❌"
            processRows.append([
                mainStatus + " " + descriptor.name,
                String(descriptor.pid),
                String(format: "%.1f%%", mainCpu),
                String(format: "%.1f MB", mainRam),
                "-", // Domain for main process
                sshStatus, // SSH status
                uptimeString(from: descriptor.startedAt)
            ])

            // Find child processes and match them to sites
            let childPids = ProcessDescriptorManager.getChildProcesses(parentPid: descriptor.pid)

            // Match child processes to sites by port or process name
            for site in config.sites {
                var sitePid: pid_t? = nil
                var siteUsage: ProcessResourceUsage? = nil
                
                switch site {
                case .app(let appSite):
                    // Try to find process by port first (most reliable)
                    if let pid = ServiceDetector.getPIDForPort(appSite.port) {
                        sitePid = pid
                        siteUsage = manager.getResourceUsage(pid: pid)
                    } else {
                        // Try to find by matching child process command
                        // Also check grandchildren (processes started by child processes)
                        var allChildPids = childPids
                        for childPid in childPids {
                            let grandchildren = ProcessDescriptorManager.getChildProcesses(parentPid: childPid)
                            allChildPids.append(contentsOf: grandchildren)
                        }
                        
                        for pid in allChildPids {
                            if let childUsage = manager.getResourceUsage(pid: pid) {
                                // Check if command matches site name or executable
                                let cmd = childUsage.command.lowercased()
                                let siteNameLower = site.name.lowercased()
                                // Match by site name, or by common executable patterns
                                if cmd.contains(siteNameLower) || 
                                   cmd.contains(siteNameLower.replacingOccurrences(of: "-", with: "")) ||
                                   cmd.contains("guestlist") || cmd.contains("guest-list") {
                                    sitePid = pid
                                    siteUsage = childUsage
                                    break
                                }
                            }
                        }
                    }
                    
                    // Get health status with timeout to prevent hanging/segfault
                    // If we found a PID, show health status; otherwise show unknown
                    let health: String
                    if sitePid != nil {
                        do {
                            let healthCheck = try await withThrowingTaskGroup(of: (ok: Bool, message: String?).self) { group in
                                group.addTask {
                                    let proxyHandler = ProxyHandler(config: config)
                                    let result = await proxyHandler.checkHealth(appSite: appSite)
                                    _ = proxyHandler // Keep alive
                                    return result
                                }
                                group.addTask {
                                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second timeout
                                    throw TimeoutError()
                                }
                                let result = try await group.next()!
                                group.cancelAll()
                                return result
                            }
                            health = healthCheck.ok ? "✅" : "❌"
                        } catch {
                            // If health check times out or fails, but we have a PID, show as starting
                            health = sitePid != nil ? "🟡" : "❓"
                        }
                    } else {
                        // No PID found - process might not be running
                        health = "❌"
                    }
                    
                    let siteCpu = siteUsage?.cpuPercent ?? 0.0
                    let siteRam = siteUsage?.memoryMB ?? 0.0
                    let sitePidStr = sitePid.map { String($0) } ?? "-"
                    
                    processRows.append([
                        "  └─ " + site.name + " " + health,
                        sitePidStr,
                        String(format: "%.1f%%", siteCpu),
                        String(format: "%.1f MB", siteRam),
                        site.domain,
                        "-", // SSH not applicable to individual sites
                        "port:\(appSite.port)"
                    ])
                    
                case .static(let staticSite):
                    let outputPath = resolvePath(
                        staticSite.outputPath,
                        baseDir: config.baseDir,
                        workingDir: nil
                    )
                    let exists = FileManager.default.fileExists(atPath: outputPath)
                    let health = exists ? "✅" : "⚠️"
                    
                    processRows.append([
                        "  └─ " + site.name + " " + health,
                        "-",
                        "-",
                        "-",
                        site.domain,
                        "-", // SSH not applicable to individual sites
                        "static"
                    ])
                }
            }

            // Show cloudflared if enabled
            if let tunnel = config.cloudflare, tunnel.enabled {
                let cloudflaredPath = (tunnel.cloudflaredPath as NSString).expandingTildeInPath
                let cloudflaredRunning = Self.checkCloudflaredRunning(executablePath: cloudflaredPath)
                let cloudflaredStatus = cloudflaredRunning ? "🟢" : "🔴"
                
                // Try to find cloudflared PID
                var cloudflaredPid: String = "-"
                var cloudflaredCpu: Double = 0.0
                var cloudflaredRam: Double = 0.0
                
                for childPid in childPids {
                    if let usage = manager.getResourceUsage(pid: childPid) {
                        if usage.command.contains("cloudflared") {
                            cloudflaredPid = String(childPid)
                            cloudflaredCpu = usage.cpuPercent
                            cloudflaredRam = usage.memoryMB
                            break
                        }
                    }
                }
                
                processRows.append([
                    "  └─ cloudflared " + cloudflaredStatus,
                    cloudflaredPid,
                    String(format: "%.1f%%", cloudflaredCpu),
                    String(format: "%.1f MB", cloudflaredRam),
                    "-", // Domain not applicable to cloudflared itself
                    "-", // SSH not applicable to cloudflared
                    "tunnel"
                ])
            }

            let columns = [
                TableColumn(title: "PROCESS", width: .auto, alignment: .left),
                TableColumn(title: "PID", width: .auto, alignment: .right),
                TableColumn(title: "CPU", width: .auto, alignment: .right),
                TableColumn(title: "RAM", width: .auto, alignment: .right),
                TableColumn(title: "DOMAIN", width: .auto, alignment: .left),
                TableColumn(title: "SSH", width: .auto, alignment: .center),
                TableColumn(title: "INFO", width: .auto, alignment: .left)
            ]
            
            let rows = processRows.map { row in
                row.map(TerminalText.init)
            }
            
            return TableData(columns: columns, rows: rows)
        }
        
        // Create initial table data
        let initialData = await buildTableData()
        
        // Create async stream for updates
        let updates = AsyncStream<TableData> { continuation in
            Task.detached {
                while StatusExitFlag.value == 0 && !Task.isCancelled {
                    let tableData = await buildTableData()
                    continuation.yield(tableData)
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Update every second
                }
                continuation.finish()
            }
        }
        
        // Display live updating table
        await Noora().table(initialData, updates: updates)
    }
    
    /// Checks if cloudflared is running by looking for the process.
    private static func checkCloudflaredRunning(executablePath: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", executablePath]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Helpers
    
    private struct TimeoutError: Error {}

    private static func resolvePath(_ path: String, baseDir: String?, workingDir: String?) -> String {
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

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
