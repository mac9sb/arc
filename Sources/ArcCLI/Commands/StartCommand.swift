import ArcCore
import ArcServer
import ArgumentParser
import Darwin
import Foundation
import Noora
import PklSwift

/// Thread-safe box for passing errors from async Tasks
private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

/// Global shutdown flag for signal handlers (must be accessible from C function pointers)
/// Using nonisolated(unsafe) as signal handlers are special and need direct access
private final class GlobalShutdownFlag {
    nonisolated(unsafe) static var value: Int32 = 0
}

/// Signal handler function (must be a C function, cannot capture context)
private func shutdownSignalHandler(_ signal: Int32) {
    GlobalShutdownFlag.value = 1
}

/// Installs SIGTERM/SIGINT handlers with SA_RESTART so that semaphore.wait() etc.
/// are not interrupted (EINTR); we only exit after the Task runs cleanup and signals.
private func installShutdownHandlers() {
    var action = sigaction()
    action.__sigaction_u.__sa_handler = shutdownSignalHandler
    sigemptyset(&action.sa_mask)
    action.sa_flags = SA_RESTART
    withUnsafePointer(to: &action) { actionPtr in
        _ = sigaction(SIGTERM, actionPtr, nil)
        _ = sigaction(SIGINT, actionPtr, nil)
    }
}

/// Thread-safe box for signaling shutdown
private final class ShutdownSignal: @unchecked Sendable {
    var shouldShutdown: Bool {
        // Check the global flag
        return GlobalShutdownFlag.value == 1
    }
    
    func reset() {
        GlobalShutdownFlag.value = 0
    }
}

/// Helper function to redirect stdout/stderr to a log file.
/// Accesses global C stdio state, which is safe for global functions.
private nonisolated func redirectStdioToLog(logPath: String) {
    freopen(logPath, "a+", stdout)
    freopen(logPath, "a+", stderr)
}

/// Command to start the Arc development server.
///
/// Starts the Arc proxy server and manages all configured sites and applications.
/// Can run in foreground or background mode.
///
/// ## Usage
///
/// ```sh
/// arc start                    # Start in foreground with default config
/// arc start --config custom.pkl # Use custom config file
/// arc start --background        # Start in background mode
/// arc start --keep-awake        # Prevent system sleep while running
/// ```
public struct StartCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start arc server"
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

    /// Enable verbose logging output for debugging.
    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false

    /// Prevent system sleep while the server is running.
    @Flag(name: .long, help: "Prevent system sleep while server is running")
    var keepAwake: Bool = false

    /// Internal: run server loop only (used when spawning background subprocess).
    @Flag(name: .long, help: .hidden)
    var internalServer: Bool = false

    /// Internal: process name override (used to keep parent/child in sync).
    @Option(name: .long, help: .hidden)
    var processName: String?

    /// Executes the start command.
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
        let isVerbose = verbose
        let isInternalServer = internalServer
        let keepAwakeEnabled = keepAwake
        let processNameOverride = processName

        if runBackground, !isInternalServer {
            try Self.runBackgroundSpawn(
                configPath: configPath,
                logFile: logFilePath,
                verbose: isVerbose,
                keepAwake: keepAwakeEnabled,
                processNameOverride: processNameOverride
            )
            return
        }

        if isInternalServer {
            try Self.runInternalServer(
                configPath: configPath,
                logFile: logFilePath,
                verbose: isVerbose,
                keepAwake: keepAwakeEnabled,
                processNameOverride: processNameOverride
            )
            return
        }

        // Foreground: block until killed; cleanup runs, then we signal and return.
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()
        installShutdownHandlers()

        Task { @Sendable in
            do {
                try await Self.runForeground(
                    configPath: configPath,
                    verbose: isVerbose,
                    keepAwake: keepAwakeEnabled,
                    shutdownSemaphore: semaphore
                )
            } catch {
                errorBox.error = error
                semaphore.signal()
            }
        }

        semaphore.wait()
        if let error = errorBox.error {
            throw error
        }
    }

    // MARK: - Foreground

    private static func runForeground(
        configPath: String,
        verbose: Bool,
        keepAwake: Bool,
        shutdownSemaphore: DispatchSemaphore? = nil
    ) async throws {
        if verbose {
            Noora().info("Arc Development Server")
            Noora().info("Starting in foreground mode...")
            Noora().info("Verbose mode enabled")
        }
        let keepAwakeSession = KeepAwakeSession.startIfNeeded(enabled: keepAwake, verbose: verbose)
        defer { keepAwakeSession?.stop(verbose: verbose) }

        // Resolve relative paths to absolute paths
        let resolvedConfigPath: String
        if (configPath as NSString).isAbsolutePath {
            resolvedConfigPath = configPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedConfigPath = (currentDir as NSString).appendingPathComponent(configPath)
        }
        
        if verbose {
            Noora().info("Config path: \(resolvedConfigPath)")
        }

        let currentConfig = try await loadConfig(path: resolvedConfigPath)

        // Create process descriptor
        let baseDir = currentConfig.baseDir ?? FileManager.default.currentDirectoryPath
        let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
        let manager = ProcessDescriptorManager(baseDir: pidDir)

        // Generate or use process name
        let processName = try await generateProcessName(from: currentConfig, manager: manager)
        if verbose {
            Noora().info("Process name: \(processName)")
        }
        let descriptor = try await manager.create(
            name: processName, config: currentConfig, configPath: resolvedConfigPath)

        if verbose {
            Noora().success(
                .alert(
                    "Process registered: \(descriptor.name)",
                    takeaways: [
                        "PID: \(descriptor.pid)"
                    ]))
        }

        let server = HTTPServer(config: currentConfig)
        let sharedState = SharedState(config: currentConfig)

        let watcher = await setupWatcher(
            configPath: resolvedConfigPath, server: server, sharedState: sharedState, initialConfig: currentConfig)

        let shutdownSignal = ShutdownSignal()
        shutdownSignal.reset()

        try await server.start()
        if verbose {
            Noora().info("HTTP server started on port \(currentConfig.proxyPort)")
        }
        await startSites(config: currentConfig, state: sharedState, verbose: verbose)
        try await startCloudflared(config: currentConfig, state: sharedState, verbose: verbose)
        watcher?.start()

        if verbose {
            Noora().success(
                .alert(
                    "Server started successfully",
                    takeaways: [
                        "Press Ctrl+C to stop"
                    ]))
        } else {
            Noora().success("Server running on port \(currentConfig.proxyPort). Press Ctrl+C to stop.")
        }

        // Wait until shutdown signal is received
        while !shutdownSignal.shouldShutdown {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        if verbose {
            Noora().info("Shutting down gracefully...")
        }
        watcher?.stop()
        server.stop()
        await sharedState.stopCloudflared()
        await sharedState.stopAll()
        try? await manager.delete(name: descriptor.name)
        if verbose {
            Noora().info("Cleanup complete")
        }
        shutdownSemaphore?.signal()
    }

    // MARK: - Background

    /// Spawns a subprocess that runs the server (--internal-server), waits for it to be ready, prints, then exits.
    /// The parent returns immediately; the child keeps running until killed.
    private static func runBackgroundSpawn(
        configPath: String,
        logFile: String?,
        verbose: Bool,
        keepAwake: Bool,
        processNameOverride: String?
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()

        Task { @Sendable in
            do {
                let (baseDir, processName, resolvedConfigPath) = try await Self.prepareBackgroundSpawn(
                    configPath: configPath,
                    processNameOverride: processNameOverride
                )
                try Self.spawnAndWaitForReady(
                    configPath: resolvedConfigPath,
                    logFile: logFile,
                    baseDir: baseDir,
                    processName: processName,
                    verbose: verbose,
                    keepAwake: keepAwake
                )
                semaphore.signal()
            } catch {
                errorBox.error = error
                semaphore.signal()
            }
        }

        semaphore.wait()
        if let error = errorBox.error {
            throw error
        }
    }

    private static func prepareBackgroundSpawn(
        configPath: String,
        processNameOverride: String?
    ) async throws -> (baseDir: String, processName: String, resolvedConfigPath: String) {
        let resolvedConfigPath: String
        if (configPath as NSString).isAbsolutePath {
            resolvedConfigPath = configPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedConfigPath = (currentDir as NSString).appendingPathComponent(configPath)
        }
        let currentConfig = try await loadConfig(path: resolvedConfigPath)
        let baseDir = currentConfig.baseDir ?? FileManager.default.currentDirectoryPath
        let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
        let manager = ProcessDescriptorManager(baseDir: pidDir)
        let processName: String
        if let override = processNameOverride, !override.isEmpty {
            processName = ProcessNameGenerator.sanitize(name: override)
        } else {
            processName = try await generateProcessName(from: currentConfig, manager: manager)
        }
        return (baseDir, processName, resolvedConfigPath)
    }

    private static func spawnAndWaitForReady(
        configPath: String,
        logFile: String?,
        baseDir: String,
        processName: String,
        verbose: Bool,
        keepAwake: Bool
    ) throws {
        let argv0 = ProcessInfo.processInfo.arguments[0]
        let executable: String
        let argsPrefix: [String]
        if argv0.contains("/") {
            executable = argv0
            argsPrefix = []
        } else {
            executable = "/usr/bin/env"
            argsPrefix = [argv0]
        }
        var args = argsPrefix + [
            "start",
            "--config", configPath,
            "--internal-server",
            "--process-name", processName
        ]
        if let logFile {
            args += ["--log-file", logFile]
        }
        if verbose {
            args += ["--verbose"]
        }
        if keepAwake {
            args += ["--keep-awake"]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: baseDir)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        let childPID = process.processIdentifier

        let descriptorPath = "\(baseDir)/.pid/arc-\(processName).json"
        let timeoutSeconds = 15.0
        let interval = 0.2
        var elapsed = 0.0
        while elapsed < timeoutSeconds {
            if !process.isRunning {
                throw ArcError.invalidConfiguration("Background process exited before ready. Check logs.")
            }
            if FileManager.default.fileExists(atPath: descriptorPath) {
                let descriptor = readDescriptor(at: descriptorPath)
                let resolvedName = descriptor?.name ?? processName
                let resolvedPort = descriptor.map { String($0.proxyPort) } ?? "unknown"
                if verbose {
                    Noora().success(
                        .alert(
                            "Background process started",
                            takeaways: [
                                "Process: \(resolvedName)",
                                "Port: \(resolvedPort)",
                                "PID: \(childPID)",
                                "Log: logDir/\(processName).log or --log-file",
                            ]))
                } else {
                    if let descriptor {
                        Noora().success("Success: \(descriptor.name) started on \(descriptor.proxyPort)")
                    } else {
                        Noora().success("Success: \(processName) started on unknown port")
                    }
                }
                return
            }
            Thread.sleep(forTimeInterval: interval)
            elapsed += interval
        }

        if process.isRunning {
            process.terminate()
        }
        throw ArcError.invalidConfiguration("Background process did not become ready within \(Int(timeoutSeconds))s. Check logs.")
    }

    /// Runs the server loop when invoked as child of runBackgroundSpawn (--internal-server).
    /// Blocks until shutdown; never returns except on error.
    private static func runInternalServer(
        configPath: String,
        logFile: String?,
        verbose: Bool,
        keepAwake: Bool,
        processNameOverride: String?
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()
        installShutdownHandlers()

        Task { @Sendable in
            do {
                try await Self.runBackground(
                    configPath: configPath,
                    logFile: logFile,
                    verbose: verbose,
                    keepAwake: keepAwake,
                    internalServer: true,
                    processNameOverride: processNameOverride,
                    shutdownSemaphore: semaphore
                )
                semaphore.signal()
            } catch {
                errorBox.error = error
                semaphore.signal()
            }
        }

        semaphore.wait()
        if let error = errorBox.error {
            throw error
        }
    }

    private static func runBackground(
        configPath: String,
        logFile: String?,
        verbose: Bool,
        keepAwake: Bool,
        internalServer: Bool = false,
        processNameOverride: String? = nil,
        shutdownSemaphore: DispatchSemaphore? = nil
    ) async throws {
        if verbose {
            Noora().info("Arc Development Server")
            Noora().info("Starting in background mode...")
            Noora().info("Verbose mode enabled")
        }

        // Resolve relative paths to absolute paths
        let resolvedConfigPath: String
        if (configPath as NSString).isAbsolutePath {
            resolvedConfigPath = configPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedConfigPath = (currentDir as NSString).appendingPathComponent(configPath)
        }
        
        if verbose {
            Noora().info("Config path: \(resolvedConfigPath)")
        }

        let currentConfig = try await loadConfig(path: resolvedConfigPath)

        // Create process descriptor manager
        let baseDir = currentConfig.baseDir ?? FileManager.default.currentDirectoryPath
        let pidDir = URL(fileURLWithPath: "\(baseDir)/.pid")
        let manager = ProcessDescriptorManager(baseDir: pidDir)

        // Generate or use process name
        let processName: String
        if let override = processNameOverride, !override.isEmpty {
            processName = ProcessNameGenerator.sanitize(name: override)
        } else {
            processName = try await generateProcessName(from: currentConfig, manager: manager)
        }

        // Prepare log file
        let expandedLogDir = (currentConfig.logDir as NSString).expandingTildeInPath
        let logPath = logFile ?? "\(expandedLogDir)/\(processName).log"
        let logDirPath = (logPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: logDirPath) {
            try FileManager.default.createDirectory(
                atPath: logDirPath, withIntermediateDirectories: true)
        }

        // Create process descriptor (writes PID file and JSON descriptor)
        let descriptor = try await manager.create(
            name: processName, config: currentConfig, configPath: resolvedConfigPath)

        // Start server and sites BEFORE redirecting stdio so user sees the output
        let server = HTTPServer(config: currentConfig)
        let sharedState = SharedState(config: currentConfig)
        let watcher = await setupWatcher(
            configPath: resolvedConfigPath, server: server, sharedState: sharedState, initialConfig: currentConfig)

        try await server.start()
        if verbose {
            Noora().info("HTTP server started on port \(currentConfig.proxyPort)")
        }
        await startSites(config: currentConfig, state: sharedState, verbose: verbose)
        try await startCloudflared(config: currentConfig, state: sharedState, verbose: verbose)
        watcher?.start()

        if !internalServer {
            if verbose {
                Noora().success(
                    .alert(
                        "Background mode initialized",
                        takeaways: [
                            "Process: \(descriptor.name)",
                            "PID: \(descriptor.pid)",
                            "Log file: \(logPath)",
                            "PID file: \(baseDir)/.pid/arc-\(processName).pid",
                        ]))
                } else {
                    Noora().success("Background process started: \(descriptor.name) (PID: \(descriptor.pid))")
                }
            fflush(stdout)
            fflush(stderr)
        }
        redirectStdioToLog(logPath: logPath)
        let keepAwakeSession = KeepAwakeSession.startIfNeeded(enabled: keepAwake, verbose: verbose)
        defer { keepAwakeSession?.stop(verbose: verbose) }

        let shutdownSignal = ShutdownSignal()
        shutdownSignal.reset()
        installShutdownHandlers()

        // Wait until shutdown signal is received
        while !shutdownSignal.shouldShutdown {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        watcher?.stop()
        server.stop()
        await sharedState.stopCloudflared()
        await sharedState.stopAll()
        try? await manager.delete(name: descriptor.name)
        shutdownSemaphore?.signal()
    }

    // MARK: - Helpers

    private static func startCloudflared(config: ArcConfig, state: SharedState, verbose: Bool) async throws {
        guard let tunnel = config.cloudflare, tunnel.enabled else {
            if verbose {
                Noora().info("Cloudflared tunnel is disabled in configuration")
            }
            return
        }

        if verbose {
            let cloudflaredPath = (tunnel.cloudflaredPath as NSString).expandingTildeInPath
            let logPath = "\((config.logDir as NSString).expandingTildeInPath)/cloudflared.log"
            let identifier = tunnel.tunnelName ?? tunnel.tunnelUUID ?? "none"
            Noora().info("Starting cloudflared tunnel...")
            Noora().info("  Executable: \(cloudflaredPath)")
            Noora().info("  Tunnel: \(identifier)")
            if let tunnelUUID = tunnel.tunnelUUID {
                let credentialsPath = CloudflaredCredentials.filePath(tunnelUUID: tunnelUUID)
                Noora().info("  Credentials: \(credentialsPath)")
                let credentialsExists = FileManager.default.fileExists(atPath: credentialsPath)
                Noora().info("  Credentials file exists: \(credentialsExists)")
                if !credentialsExists {
                    Noora().warning("  ⚠️ Credentials file missing - cloudflared will fail to start")
                    // List what files actually exist in ~/.cloudflared
                    let cloudflaredDir = (credentialsPath as NSString).deletingLastPathComponent
                    if let files = try? FileManager.default.contentsOfDirectory(atPath: cloudflaredDir) {
                        let jsonFiles = files.filter { $0.hasSuffix(".json") }
                        if !jsonFiles.isEmpty {
                            Noora().info("  Found JSON files in ~/.cloudflared: \(jsonFiles.joined(separator: ", "))")
                        } else {
                            Noora().info("  No JSON files found in ~/.cloudflared")
                        }
                    }
                }
            } else {
                Noora().info("  Credentials: (skipped; tunnelUUID not set)")
            }
            Noora().info("  Log file: \(logPath)")
        }

        do {
                if let pid = try await state.startCloudflared(config: config) {
                if verbose {
                    Noora().success(
                        .alert(
                            "Started cloudflared tunnel",
                            takeaways: [
                                "PID: \(pid)"
                            ]))
                    Noora().success("Cloudflared process started successfully and is running")
                    Noora().info("Check Activity Monitor for 'cloudflared' process")
                    Noora().info("If a site shows 'cannot be reached': add each hostname as a Public Hostname in Zero Trust → Tunnels → your tunnel.")
                }
            }
        } catch let error as CloudflaredConfigError {
            Noora().error(error.errorAlert)
            throw error // Re-throw to crash the server
        } catch {
            // Always show cloudflared errors as they're critical
            Noora().error(
                .alert(
                    "Failed to start cloudflared",
                    takeaways: [
                        "Error: \(error.localizedDescription)"
                    ]))
            throw error // Re-throw to crash the server
        }
    }

    private static func startSites(config: ArcConfig, state: SharedState, verbose: Bool) async {
        if verbose {
            Noora().info(.alert("Starting services..."))
            Noora().info("Found \(config.sites.count) site(s) to start")
        }
        for site in config.sites {
            if verbose {
                Noora().info("Starting site: \(site.name) (domain: \(site.domain))")
            }
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
                    // Ensure no process on this app's port and no orphans (prevents duplicate instances)
                    Self.killAppProcessesForPort(appSite.port, executable: command)
                    try await Task.sleep(nanoseconds: 300_000_000)  // 300ms for port release

                    var env = processConfig.env ?? [:]
                    env["PORT"] = String(appSite.port)  // Force app to listen on configured port

                    if verbose {
                        Noora().info("  Command: \(command)")
                        Noora().info("  Args: \(args.joined(separator: " "))")
                        Noora().info("  Working dir: \(processConfig.workingDir)")
                        Noora().info("  PORT=\(appSite.port)")
                    }
                    let pid = try await state.startProcess(
                        name: site.name,
                        command: command,
                        args: args,
                        workingDir: processConfig.workingDir,
                        type: .server,
                        env: env
                    )
                    if verbose {
                        Noora().success(
                            .alert(
                                "Started \(site.name)",
                                takeaways: [
                                    "PID: \(pid)"
                                ]))
                    }
                } catch let error as ArcError {
                    // Show detailed error with log path if available
                    var takeaways: [String] = ["Error: \(error.localizedDescription)"]
                    if case .processStartupFailed(_, _, let logPath) = error {
                        takeaways.append("Check logs at: \(logPath)")
                    }
                    Noora().error(
                        .alert(
                            "Failed to start \(site.name)",
                            takeaways: takeaways.map(TerminalText.init)))
                    if verbose {
                        Noora().error("  Failed to start \(site.name): \(error)")
                    }
                } catch {
                    Noora().error(
                        .alert(
                            "Failed to start \(site.name)",
                            takeaways: [
                                "Error: \(error.localizedDescription)"
                            ]))
                    if verbose {
                        Noora().error("  Failed to start \(site.name): \(error)")
                    }
                }

            case .static(let staticSite):
                if verbose {
                    let outputPath = resolvePath(
                        staticSite.outputPath,
                        baseDir: config.baseDir,
                        workingDir: nil
                    )
                    let exists = FileManager.default.fileExists(atPath: outputPath)
                    Noora().info("  Static site path: \(outputPath)")
                    Noora().info("  Path exists: \(exists)")
                    Noora().info(
                        .alert(
                            "Static site \(staticSite.name) ready",
                            takeaways: [
                                "Path: \(staticSite.outputPath)"
                            ]))
                }
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
                        // Stop all app processes and cloudflared before replacing process manager
                        await sharedState.stopAll()
                        await sharedState.update(config: newConfig)
                        await server.reload(config: newConfig)
                        await startSites(config: newConfig, state: sharedState, verbose: false)
                        await Self.restartCloudflared(config: newConfig, sharedState: sharedState, verbose: false)
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

    private static func readDescriptor(at path: String) -> ProcessDescriptor? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProcessDescriptor.self, from: data)
    }

    /// Kills any process bound to the given port and any process matching the executable name.
    /// Use before starting or restarting an app to avoid duplicate instances.
    /// Skips kill-by-name when the executable is a generic runner (swift, node, etc.) to avoid killing unrelated processes.
    private static func killAppProcessesForPort(_ port: Int, executable command: String) {
        var pids: Set<pid_t> = []
        if let pid = ServiceDetector.getPIDForPort(port) {
            pids.insert(pid)
        }
        let name = (command as NSString).lastPathComponent
        let genericRunners = ["swift", "env", "node", "npm", "python", "python3", "ruby", "bundle"]
        if !name.isEmpty, !genericRunners.contains(name.lowercased()) {
            for pid in ServiceDetector.getPIDsMatching(pattern: name) {
                pids.insert(pid)
            }
        }
        for pid in pids {
            ServiceDetector.killProcessGracefully(pid: pid, waitSeconds: 2)
        }
    }

    private static func restartCloudflared(config: ArcConfig, sharedState: SharedState, verbose: Bool = false) async {
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
            // Don't crash on restart - just log the error
        } catch {
            Noora().error(
                .alert(
                    "Failed to restart cloudflared",
                    takeaways: [
                        "Error: \(error.localizedDescription)"
                    ]))
            // Don't crash on restart - just log the error
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
            // Ensure no process on this app's port and no orphans (prevents duplicate instances)
            Self.killAppProcessesForPort(appSite.port, executable: command)
            try await Task.sleep(nanoseconds: 300_000_000)  // 300ms for port release

            var env = processConfig.env ?? [:]
            env["PORT"] = String(appSite.port)  // Force app to listen on configured port

            let pid = try await sharedState.restartProcess(
                name: name,
                command: command,
                args: args,
                workingDir: processConfig.workingDir,
                type: .server,
                env: env
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
        // First expand tilde paths
        let expandedPath = (path as NSString).expandingTildeInPath
        let resolvedPath: String
        if (expandedPath as NSString).isAbsolutePath {
            resolvedPath = expandedPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
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
