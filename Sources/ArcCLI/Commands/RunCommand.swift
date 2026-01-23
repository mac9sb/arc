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

/// Helper function to redirect stdout/stderr to a log file.
/// Accesses global C stdio state, which is safe for global functions.
private nonisolated func redirectStdioToLog(logPath: String) {
    freopen(logPath, "a+", stdout)
    freopen(logPath, "a+", stderr)
}

/// Command to run the Arc development server.
///
/// Starts the Arc proxy server and manages all configured sites and applications.
/// Can run in foreground or background mode.
///
/// ## Usage
///
/// ```bash
/// arc run                    # Run in foreground with default config
/// arc run --config custom.pkl # Use custom config file
/// arc run --background        # Run in background mode
/// ```
public struct RunCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run arc server"
    )

    /// Path to the Pkl configuration file.
    ///
    /// Defaults to `config.pkl` in the current directory.
    @Option(name: .shortAndLong, help: "Path to config file")
    var config: String = "config.pkl"

    /// Whether to run the server in background mode.
    ///
    /// When enabled, the server runs as a background process and returns control
    /// to the terminal immediately.
    @Flag(name: .long, help: "Run in background mode")
    var background: Bool = false

    /// Path to the log file for background mode.
    ///
    /// Only used when `background` is `true`. If not specified, logs are written
    /// to a default location.
    @Option(name: .long, help: "Log file path (for background mode)")
    var logFile: String?

    /// Executes the run command.
    ///
    /// Starts the Arc server in either foreground or background mode based on
    /// the `background` flag.
    ///
    /// - Throws: An error if configuration loading, server startup, or process
    ///   management fails.
    public func run() throws {
        let configPath = config
        let runBackground = background
        let logFilePath = logFile

        // For long-running server, we use a semaphore that's never signaled
        // The process will run until killed (Ctrl+C)
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()

        Task { @Sendable in
            do {
                if runBackground {
                    try await Self.runBackground(configPath: configPath, logFile: logFilePath)
                } else {
                    try await Self.runForeground(configPath: configPath)
                }
            } catch {
                errorBox.error = error
                semaphore.signal()
            }
            // Note: semaphore.signal() is NOT called on success - server runs until killed
        }

        semaphore.wait()
        if let error = errorBox.error {
            throw error
        }
    }

    // MARK: - Foreground

    private static func runForeground(configPath: String) async throws {
        Noora().info("Arc Development Server")
        Noora().info("Starting in foreground mode...")

        // Resolve relative paths to absolute paths
        let resolvedConfigPath: String
        if (configPath as NSString).isAbsolutePath {
            resolvedConfigPath = configPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedConfigPath = (currentDir as NSString).appendingPathComponent(configPath)
        }

        let currentConfig = try await loadConfig(path: resolvedConfigPath)

        // Create process descriptor
        let baseDir = currentConfig.baseDir ?? FileManager.default.currentDirectoryPath
        let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
        let manager = ProcessDescriptorManager(baseDir: pidDir)

        // Generate or use process name
        let processName = try await generateProcessName(from: currentConfig, manager: manager)
        Noora().info("Process name: \(processName)")
        let descriptor = try await manager.create(
            name: processName, config: currentConfig, configPath: resolvedConfigPath)

        Noora().success(
            .alert(
                "Process registered: \(descriptor.name)",
                takeaways: [
                    "PID: \(descriptor.pid)"
                ]))

        let server = HTTPServer(config: currentConfig)
        let sharedState = SharedState(config: currentConfig)

        let watcher = await setupWatcher(
            configPath: resolvedConfigPath, server: server, sharedState: sharedState, initialConfig: currentConfig)

        try await server.start()
        await startSites(config: currentConfig, state: sharedState)
        await startCloudflared(config: currentConfig, state: sharedState)
        watcher?.start()

        Noora().success(
            .alert(
                "Server started successfully",
                takeaways: [
                    "Press Ctrl+C to stop"
                ]))

        defer {
            watcher?.stop()
            server.stop()
            Task {
                await sharedState.stopCloudflared()
                await sharedState.stopAll()
                // Clean up descriptor
                try? await manager.delete(name: descriptor.name)
            }
        }

        try await Task.sleep(nanoseconds: .max)
    }

    // MARK: - Background

    private static func runBackground(configPath: String, logFile: String?) async throws {
        Noora().info("Arc Development Server")
        Noora().info("Starting in background mode...")

        // Resolve relative paths to absolute paths
        let resolvedConfigPath: String
        if (configPath as NSString).isAbsolutePath {
            resolvedConfigPath = configPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedConfigPath = (currentDir as NSString).appendingPathComponent(configPath)
        }

        let currentConfig = try await loadConfig(path: resolvedConfigPath)

        // Create process descriptor manager
        let baseDir = currentConfig.baseDir ?? FileManager.default.currentDirectoryPath
        let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
        let manager = ProcessDescriptorManager(baseDir: pidDir)

        // Generate or use process name
        let processName = try await generateProcessName(from: currentConfig, manager: manager)

        // Prepare log file
        let logPath = logFile ?? "\(currentConfig.logDir)/\(processName).log"
        let logDir = (logPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: logDir) {
            try FileManager.default.createDirectory(
                atPath: logDir, withIntermediateDirectories: true)
        }

        // Redirect stdout and stderr to log file
        // Using nonisolated(unsafe) helper to access global C stdio state
        redirectStdioToLog(logPath: logPath)

        // Create process descriptor (writes PID file and JSON descriptor)
        let descriptor = try await manager.create(
            name: processName, config: currentConfig, configPath: resolvedConfigPath)

        Noora().success(
            .alert(
                "Background mode initialized",
                takeaways: [
                    "Process: \(descriptor.name)",
                    "PID: \(descriptor.pid)",
                    "Log file: \(logPath)",
                    "PID file: \(baseDir)/.pid/arc-\(processName).pid",
                ]))

        let server = HTTPServer(config: currentConfig)
        let sharedState = SharedState(config: currentConfig)
        let watcher = await setupWatcher(
            configPath: resolvedConfigPath, server: server, sharedState: sharedState, initialConfig: currentConfig)

        try await server.start()
        await startSites(config: currentConfig, state: sharedState)
        await startCloudflared(config: currentConfig, state: sharedState)
        watcher?.start()

        defer {
            watcher?.stop()
            server.stop()
            Task {
                await sharedState.stopCloudflared()
                await sharedState.stopAll()
                // Clean up descriptor
                try? await manager.delete(name: descriptor.name)
            }
        }

        try await Task.sleep(nanoseconds: .max)
    }

    // MARK: - Helpers

    private static func startCloudflared(config: ArcConfig, state: SharedState) async {
        guard let tunnel = config.cloudflare, tunnel.enabled else {
            return
        }

        do {
            if let pid = try await state.startCloudflared(config: config) {
                Noora().success(
                    .alert(
                        "Started cloudflared tunnel",
                        takeaways: [
                            "PID: \(pid)"
                        ]))
            }
        } catch let error as CloudflaredConfigError {
            Noora().error(error.errorAlert)
        } catch {
            Noora().error(
                .alert(
                    "Failed to start cloudflared",
                    takeaways: [
                        "Error: \(error.localizedDescription)"
                    ]))
        }
    }

    private static func startSites(config: ArcConfig, state: SharedState) async {
        Noora().info(.alert("Starting services..."))
        for site in config.sites {
            switch site {
            case .app(let appSite):
                let processConfig = appSite.process

                let command: String
                let args: [String]

                if let executable = processConfig.executable {
                    command = executable
                    args = processConfig.args ?? []
                } else if let cmd = processConfig.command {
                    command = cmd
                    args = processConfig.args ?? []
                } else {
                    Noora().warning(
                        .alert(
                            "No process configuration for \(site.name)",
                            takeaway: "Skipping site startup"
                        ))
                    continue
                }

                do {
                    let pid = try await state.startProcess(
                        name: site.name,
                        command: command,
                        args: args,
                        workingDir: processConfig.workingDir,
                        type: .server,
                        env: processConfig.env ?? [:]
                    )
                    Noora().success(
                        .alert(
                            "Started \(site.name)",
                            takeaways: [
                                "PID: \(pid)"
                            ]))
                } catch {
                    Noora().error(
                        .alert(
                            "Failed to start \(site.name)",
                            takeaways: [
                                "Error: \(error.localizedDescription)"
                            ]))
                }

            case .static(let staticSite):
                Noora().info(
                    .alert(
                        "Static site \(staticSite.name) ready",
                        takeaways: [
                            "Path: \(staticSite.outputPath)"
                        ]))
            }
        }
    }

    private static func setupWatcher(configPath: String, server: HTTPServer, sharedState: SharedState, initialConfig: ArcConfig)
        async -> FileWatcher?
    {
        guard let watchConfig = initialConfig.watch else { return nil }

        var watchTargets: [FileWatcher.WatchTarget] = []

        if watchConfig.watchConfigPkl {
            let url = URL(fileURLWithPath: configPath)
            let configPathCopy = configPath
            watchTargets.append(
                FileWatcher.WatchTarget(path: url.path) { @Sendable in
                    Noora().info(.alert("Configuration file changed, reloading..."))
                    do {
                        let source = ModuleSource.path(configPathCopy)
                        let newConfig = try await ArcConfig.loadFrom(
                            source: source, configPath: URL(fileURLWithPath: configPathCopy))
                        await sharedState.update(config: newConfig)
                        await server.reload(config: newConfig)
                        await Self.restartCloudflared(config: newConfig, sharedState: sharedState)
                        Noora().success(.alert("Configuration reloaded"))
                    } catch {
                        Noora().error(
                            .alert(
                                "Failed to reload configuration",
                                takeaways: [
                                    "Error: \(error.localizedDescription)"
                                ]))
                    }
                }
            )
        }

        for site in initialConfig.sites {
            switch site {
            case .app(let appSite):
                if let exec = appSite.process.executable {
                    let resolved = resolvePath(
                        exec, baseDir: initialConfig.baseDir, workingDir: appSite.process.workingDir
                    )
                    let siteName = site.name
                    watchTargets.append(
                        FileWatcher.WatchTarget(path: resolved) { @Sendable in
                            Noora().info(.alert("Executable changed for \(siteName), restarting..."))
                            await Self.restart(site: siteName, config: appSite, sharedState: sharedState)
                        }
                    )
                }

                if let targets = appSite.watchTargets {
                    for target in targets {
                        let resolvedTarget = resolvePath(target, baseDir: initialConfig.baseDir)
                        var isDir: ObjCBool = false
                        _ = FileManager.default.fileExists(atPath: resolvedTarget, isDirectory: &isDir)
                        let siteName = site.name
                        watchTargets.append(
                            FileWatcher.WatchTarget(
                                path: resolvedTarget, isDirectory: isDir.boolValue
                            ) {
                                @Sendable in
                                Noora().info(.alert("Watch target changed for \(siteName), restarting..."))
                                await Self.restart(
                                    site: siteName, config: appSite, sharedState: sharedState)
                            }
                        )
                    }
                }
            case .static:
                continue
            }
        }

        let watcher = FileWatcher(
            targets: watchTargets,
            debounceConfig: FileWatcher.DebounceConfig(
                debounceMs: watchConfig.debounceMs,
                cooldownMs: watchConfig.cooldownMs
            ),
            followSymlinks: watchConfig.followSymlinks
        )

        Noora().success(.alert("File watching enabled"))
        return watcher
    }

    private static func resolvePath(_ path: String, baseDir: String?, workingDir: String? = nil) -> String {
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

    private static func restartCloudflared(config: ArcConfig, sharedState: SharedState) async {
        do {
            if let pid = try await sharedState.restartCloudflared(config: config) {
                Noora().success(
                    .alert(
                        "Restarted cloudflared tunnel",
                        takeaways: [
                            "PID: \(pid)"
                        ]))
            } else {
                // Cloudflared was disabled, ensure it's stopped
                await sharedState.stopCloudflared()
            }
        } catch let error as CloudflaredConfigError {
            Noora().error(error.errorAlert)
        } catch {
            Noora().error(
                .alert(
                    "Failed to restart cloudflared",
                    takeaways: [
                        "Error: \(error.localizedDescription)"
                    ]))
        }
    }

    private static func restart(site name: String, config appSite: AppSite, sharedState: SharedState) async {
        let processConfig = appSite.process
        let command: String
        let args: [String]

        if let executable = processConfig.executable {
            command = executable
            args = processConfig.args ?? []
        } else if let cmd = processConfig.command {
            command = cmd
            args = processConfig.args ?? []
        } else {
            Noora().warning(
                .alert(
                    "No process configuration for \(name)",
                    takeaway: "Skipping restart"
                ))
            return
        }

        do {
            let pid = try await sharedState.restartProcess(
                name: name,
                command: command,
                args: args,
                workingDir: processConfig.workingDir,
                type: .server,
                env: processConfig.env ?? [:]
            )
            Noora().success(
                .alert(
                    "Restarted \(name)",
                    takeaways: [
                        "PID: \(pid)"
                    ]))
        } catch {
            Noora().error(
                .alert(
                    "Failed to restart \(name)",
                    takeaways: [
                        "Error: \(error.localizedDescription)"
                    ]))
        }
    }

    private static func loadConfig(path: String) async throws -> ArcConfig {
        // Resolve relative paths to absolute paths
        let resolvedPath: String
        if (path as NSString).isAbsolutePath {
            resolvedPath = path
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedPath = (currentDir as NSString).appendingPathComponent(path)
        }
        
        let source = ModuleSource.path(resolvedPath)
        let configURL = URL(fileURLWithPath: resolvedPath)
        return try await ArcConfig.loadFrom(
            source: source, configPath: configURL)
    }

    private static func generateProcessName(from config: ArcConfig, manager: ProcessDescriptorManager)
        async throws -> String
    {
        if let name = config.processName, !name.isEmpty {
            return ProcessNameGenerator.sanitize(name: name)
        }

        // Get existing names to avoid conflicts
        let descriptors = try await manager.listAll()
        let existingNames = Set(descriptors.map { $0.name })

        return ProcessNameGenerator.generateUnique(excluding: existingNames)
    }
}
