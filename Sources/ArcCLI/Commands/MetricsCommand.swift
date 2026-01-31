import ArcCore
import ArcServer
import ArgumentParser
import Foundation
import Noora

/// Thread-safe box for passing errors from async Tasks
private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

/// Command to display metrics and health status for Arc.
///
/// Shows request metrics, health check results, and performance statistics
/// for running Arc instances.
///
/// ## Usage
///
/// ```sh
/// arc metrics              # Show current metrics summary
/// arc metrics --health     # Show health check status
/// arc metrics --json       # Output metrics as JSON
/// ```
public struct MetricsCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "metrics",
        abstract: "Display metrics and health status"
    )

    /// Show health check status.
    @Flag(name: .long, help: "Show health check status for all sites")
    var health: Bool = false

    /// Output as JSON.
    @Flag(name: .long, help: "Output metrics as JSON")
    var json: Bool = false

    /// Enable verbose output.
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    public func run() throws {
        let configPath = "Arc.swift"
        let showHealth = health
        let outputJSON = json
        let isVerbose = verbose

        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()

        Task { @Sendable in
            defer { semaphore.signal() }
            do {
                try await Self.displayMetrics(
                    configPath: configPath,
                    showHealth: showHealth,
                    outputJSON: outputJSON,
                    verbose: isVerbose
                )
            } catch {
                errorBox.error = error
            }
        }

        semaphore.wait()
        if let error = errorBox.error {
            throw error
        }
    }

    // MARK: - Display Methods

    private static func displayMetrics(
        configPath: String,
        showHealth: Bool,
        outputJSON: Bool,
        verbose: Bool
    ) async throws {
        let noora = Noora()

        // Resolve config path
        let expandedPath = (configPath as NSString).expandingTildeInPath
        let resolvedPath: String
        if (expandedPath as NSString).isAbsolutePath {
            resolvedPath = expandedPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
        }

        // Check if config exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            noora.error("Manifest file not found: \(resolvedPath)")
            return
        }

        // Load config
        let configURL = URL(fileURLWithPath: resolvedPath)
        let config: ArcConfig
        do {
            config = try await ArcConfig.loadFrom(
                source: ModuleSource.path(resolvedPath),
                configPath: configURL
            )
        } catch {
            noora.error("Failed to load config: \(error.localizedDescription)")
            return
        }

        // Check for running Arc process
        let baseDir = config.baseDir ?? configURL.deletingLastPathComponent().path
        let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
        let manager = ProcessDescriptorManager(baseDir: pidDir)

        let descriptors = (try? await manager.listAll()) ?? []
        let activeDescriptors = descriptors.filter { descriptor in
            ServiceDetector.isProcessRunning(pid: descriptor.pid)
        }

        if activeDescriptors.isEmpty {
            noora.warning("No running Arc processes found")
            if !showHealth {
                return
            }
        }

        if showHealth {
            await displayHealthStatus(config: config, outputJSON: outputJSON, verbose: verbose)
        } else {
            await displayMetricsSummary(
                config: config,
                descriptors: activeDescriptors,
                manager: manager,
                outputJSON: outputJSON,
                verbose: verbose
            )
        }
    }

    private static func displayHealthStatus(
        config: ArcConfig,
        outputJSON: Bool,
        verbose: Bool
    ) async {
        let noora = Noora()
        var healthResults: [HealthCheckResult] = []

        print("")
        if !outputJSON {
            noora.info("Health Check Status")
            print("─────────────────────────────────────")
        }

        for site in config.sites {
            let result: HealthCheckResult

            switch site {
            case .static(let staticSite):
                // Check if output directory exists
                let outputPath = resolvePath(
                    staticSite.outputPath,
                    baseDir: config.baseDir
                )
                let exists = FileManager.default.fileExists(atPath: outputPath)
                result = HealthCheckResult(
                    name: staticSite.name,
                    healthy: exists,
                    message: exists ? "Output directory exists" : "Output directory missing"
                )

            case .app(let appSite):
                // Perform HTTP health check
                let startTime = Date()
                do {
                    guard let healthURL = appSite.healthURL() else {
                        result = HealthCheckResult(
                            name: appSite.name,
                            healthy: false,
                            message: "Health URL not configured"
                        )
                        return
                    }
                    var request = URLRequest(url: healthURL)
                    request.timeoutInterval = 5

                    let (_, response) = try await URLSession.shared.data(for: request)
                    let httpResponse = response as? HTTPURLResponse
                    let statusCode = httpResponse?.statusCode ?? 0
                    let responseTimeMs = Date().timeIntervalSince(startTime) * 1000

                    result = HealthCheckResult(
                        name: appSite.name,
                        healthy: statusCode >= 200 && statusCode < 400,
                        message: "HTTP \(statusCode)",
                        responseTimeMs: responseTimeMs,
                        statusCode: statusCode
                    )
                } catch {
                    let responseTimeMs = Date().timeIntervalSince(startTime) * 1000
                    result = HealthCheckResult(
                        name: appSite.name,
                        healthy: false,
                        message: error.localizedDescription,
                        responseTimeMs: responseTimeMs
                    )
                }
            }

            healthResults.append(result)

            if !outputJSON {
                let status = result.healthy ? "✓" : "✗"
                let statusColor = result.healthy ? "\u{001B}[32m" : "\u{001B}[31m"
                let reset = "\u{001B}[0m"

                var details = result.message ?? ""
                if let responseTime = result.responseTimeMs {
                    details += " (\(String(format: "%.1f", responseTime))ms)"
                }

                print("\(statusColor)\(status)\(reset) \(result.name): \(details)")
            }
        }

        if outputJSON {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(healthResults),
                let jsonString = String(data: data, encoding: .utf8)
            {
                print(jsonString)
            }
        }
    }

    private static func displayMetricsSummary(
        config: ArcConfig,
        descriptors: [ProcessDescriptor],
        manager: ProcessDescriptorManager,
        outputJSON: Bool,
        verbose: Bool
    ) async {
        let noora = Noora()

        // Collect metrics from running processes
        var processMetrics: [[String: Any]] = []

        for descriptor in descriptors {
            let usage = manager.getResourceUsage(pid: descriptor.pid)
            let uptime = Date().timeIntervalSince(descriptor.startedAt)

            var metrics: [String: Any] = [
                "name": descriptor.name,
                "pid": descriptor.pid,
                "port": descriptor.proxyPort,
                "uptime_seconds": Int(uptime),
                "cpu_percent": usage?.cpuPercent ?? 0,
                "memory_mb": usage?.memoryMB ?? 0,
            ]

            // Get child process count
            let children = ProcessDescriptorManager.getChildProcesses(parentPid: descriptor.pid)
            metrics["child_processes"] = children.count

            processMetrics.append(metrics)
        }

        if outputJSON {
            let summary: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "processes": processMetrics,
                "sites": config.sites.count,
                "proxy_port": config.proxyPort,
            ]

            if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]),
                let jsonString = String(data: data, encoding: .utf8)
            {
                print(jsonString)
            }
        } else {
            print("")
            noora.info("Arc Metrics Summary")
            print("─────────────────────────────────────")
            print("")
            print("  Proxy Port: \(config.proxyPort)")
            print("  Sites: \(config.sites.count)")
            print("  Running Processes: \(descriptors.count)")
            print("")

            if !processMetrics.isEmpty {
                print("  Process Details:")
                for metrics in processMetrics {
                    let name = metrics["name"] as? String ?? "unknown"
                    let pid = metrics["pid"] as? Int ?? 0
                    let cpu = metrics["cpu_percent"] as? Double ?? 0
                    let mem = metrics["memory_mb"] as? Double ?? 0
                    let uptime = metrics["uptime_seconds"] as? Int ?? 0
                    let children = metrics["child_processes"] as? Int ?? 0

                    print("")
                    print("    \(name) (PID: \(pid))")
                    print("      CPU: \(String(format: "%.1f", cpu))%")
                    print("      Memory: \(String(format: "%.1f", mem)) MB")
                    print("      Uptime: \(formatUptime(uptime))")
                    print("      Child Processes: \(children)")
                }
            }

            print("")
            print("─────────────────────────────────────")
            print("Run 'arc metrics --health' for health check status")
        }
    }

    // MARK: - Helpers

    private static func resolvePath(_ path: String, baseDir: String?) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return expanded
        }
        if let baseDir {
            return (baseDir as NSString).appendingPathComponent(expanded)
        }
        return expanded
    }

    private static func formatUptime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}
