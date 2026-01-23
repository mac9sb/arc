import ArcCore
import Foundation

/// Shared mutable state holder for watchers and processes.
///
/// Using an actor ensures thread-safe access to mutable state from async contexts.
public actor SharedState {
    public var config: ArcConfig
    /// Process manager is nonisolated(unsafe) because we call its async methods (startProcess,
    /// restartProcess) which are nonisolated. Access is serialized by the actor; we never
    /// touch processManager concurrently.
    nonisolated(unsafe) private var processManager: ServerProcessManager

    /// Creates a new shared state instance.
    ///
    /// - Parameter config: The initial configuration.
    public init(config: ArcConfig) {
        self.config = config
        self.processManager = ServerProcessManager(config: config)
    }

    /// Updates the configuration and recreates the process manager.
    ///
    /// - Parameter config: The new configuration.
    public func update(config: ArcConfig) {
        self.config = config
        self.processManager = ServerProcessManager(config: config)
    }

    /// Starts a process.
    ///
    /// - Returns: The process ID.
    public func startProcess(
        name: String,
        command: String,
        args: [String],
        workingDir: String,
        type: ServerProcessManager.ProcessRecord.ProcessType,
        env: [String: String]
    ) async throws -> pid_t {
        try await processManager.startProcess(
            name: name,
            command: command,
            args: args,
            workingDir: workingDir,
            type: type,
            env: env
        )
    }

    /// Restarts a process.
    ///
    /// - Returns: The process ID.
    public func restartProcess(
        name: String,
        command: String,
        args: [String],
        workingDir: String,
        type: ServerProcessManager.ProcessRecord.ProcessType,
        env: [String: String]
    ) async throws -> pid_t {
        try await processManager.restartProcess(
            name: name,
            command: command,
            args: args,
            workingDir: workingDir,
            type: type,
            env: env
        )
    }

    /// Stops all managed processes.
    ///
    /// Stops tracked processes (SIGTERM → wait → SIGKILL), then kills any app
    /// processes still listening on configured ports or matching "GuestListWeb"
    /// (catches orphans when we've lost PIDs, e.g. after config reload).
    public func stopAll() {
        processManager.stopAll()

        // Fallback: kill app processes by port (we may have lost PIDs)
        for site in config.sites {
            switch site {
            case .app(let appSite):
                if let pid = ServiceDetector.getPIDForPort(appSite.port) {
                    ServiceDetector.killProcessGracefully(pid: pid, waitSeconds: 2)
                }
            case .static:
                break
            }
        }

        // Fallback: pgrep for app executables (covers PORT mismatch, e.g. .env vs config)
        var appPids: Set<pid_t> = []
        for pattern in ["GuestListWeb", "guestlist", "guest-list"] {
            for pid in ServiceDetector.getPIDsMatching(pattern: pattern) {
                appPids.insert(pid)
            }
        }
        for pid in appPids {
            ServiceDetector.killProcessGracefully(pid: pid, waitSeconds: 2)
        }
    }

    /// Starts cloudflared tunnel if enabled in configuration.
    ///
    /// - Parameter config: The Arc configuration.
    /// - Returns: The process ID if cloudflared was started, `nil` if disabled.
    /// - Throws: An error if cloudflared cannot be started or configuration is invalid.
    public func startCloudflared(config: ArcConfig) async throws -> pid_t? {
        guard let tunnel = config.cloudflare, tunnel.enabled else {
            return nil
        }

        // Validate tunnel UUID is present
        guard let tunnelUUID = tunnel.tunnelUUID, !tunnelUUID.isEmpty else {
            throw CloudflaredConfigError.tunnelUUIDRequired
        }

        // Validate cloudflared executable exists
        let cloudflaredPath = (tunnel.cloudflaredPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: cloudflaredPath) else {
            throw ArcError.invalidConfiguration(
                "Cloudflared executable not found at: \(tunnel.cloudflaredPath)")
        }

        // Validate credentials file exists
        let credentialsPath = CloudflaredConfigGenerator.generateCredentialsFilePath(tunnelUUID: tunnelUUID)
        guard FileManager.default.fileExists(atPath: credentialsPath) else {
            throw CloudflaredConfigError.credentialsFileMissing(
                tunnelUUID: tunnelUUID,
                credentialsPath: credentialsPath
            )
        }

        // Always kill any existing cloudflared first (orphans from previous runs or double-start)
        stopCloudflared()

        // Generate and write config file to ~/.cloudflared/config.yml (cloudflared default)
        try CloudflaredConfigGenerator.writeConfig(config: config, tunnel: tunnel)

        // Start cloudflared: just "tunnel run"; uses default config at ~/.cloudflared/config.yml
        let baseDir = config.baseDir ?? FileManager.default.currentDirectoryPath
        let pid = try await processManager.startProcess(
            name: "cloudflared",
            command: cloudflaredPath,
            args: ["tunnel", "run"],
            workingDir: baseDir,
            type: .cloudflared,
            env: [:]
        )

        return pid
    }

    /// Stops the cloudflared tunnel process.
    ///
    /// Tries the managed process first, then uses pgrep to find and kill any
    /// remaining "cloudflared tunnel run" processes (e.g. after config reload
    /// when we lose the PID). Uses SIGTERM, waits, then SIGKILL for stubborn processes.
    public func stopCloudflared() {
        _ = processManager.stopProcess(name: "cloudflared")

        // Fallback: pgrep for cloudflared tunnel processes we may have lost track of
        var cloudflaredPids: Set<pid_t> = []
        for pattern in ["cloudflared tunnel run", "cloudflared tunnel"] {
            for pid in ServiceDetector.getPIDsMatching(pattern: pattern) {
                cloudflaredPids.insert(pid)
            }
        }
        for pid in cloudflaredPids {
            ServiceDetector.killProcessGracefully(pid: pid, waitSeconds: 2)
        }
    }

    /// Restarts cloudflared tunnel on configuration changes.
    ///
    /// - Parameter config: The Arc configuration.
    /// - Returns: The process ID if cloudflared was restarted, `nil` if disabled.
    /// - Throws: An error if cloudflared cannot be restarted or configuration is invalid.
    public func restartCloudflared(config: ArcConfig) async throws -> pid_t? {
        guard let tunnel = config.cloudflare, tunnel.enabled else {
            // If disabled, stop any running cloudflared
            stopCloudflared()
            return nil
        }

        // Validate tunnel UUID is present
        guard let tunnelUUID = tunnel.tunnelUUID, !tunnelUUID.isEmpty else {
            throw CloudflaredConfigError.tunnelUUIDRequired
        }

        // Validate cloudflared executable exists
        let cloudflaredPath = (tunnel.cloudflaredPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: cloudflaredPath) else {
            throw ArcError.invalidConfiguration(
                "Cloudflared executable not found at: \(tunnel.cloudflaredPath)")
        }

        // Validate credentials file exists
        let credentialsPath = CloudflaredConfigGenerator.generateCredentialsFilePath(tunnelUUID: tunnelUUID)
        guard FileManager.default.fileExists(atPath: credentialsPath) else {
            throw CloudflaredConfigError.credentialsFileMissing(
                tunnelUUID: tunnelUUID,
                credentialsPath: credentialsPath
            )
        }

        // Generate and write config file to ~/.cloudflared/config.yml (cloudflared default)
        try CloudflaredConfigGenerator.writeConfig(config: config, tunnel: tunnel)

        // Restart cloudflared: just "tunnel run"; uses default config at ~/.cloudflared/config.yml
        let baseDir = config.baseDir ?? FileManager.default.currentDirectoryPath
        let pid = try await processManager.restartProcess(
            name: "cloudflared",
            command: cloudflaredPath,
            args: ["tunnel", "run"],
            workingDir: baseDir,
            type: .cloudflared,
            env: [:]
        )

        // Wait a moment for process to start, then verify it's running
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        let isRunning = ServiceDetector.isProcessRunning(pid: pid)
        
        if !isRunning {
            let logPath = "\((config.logDir as NSString).expandingTildeInPath)/cloudflared.log"
            throw CloudflaredConfigError.processExitedImmediately(pid: pid, logPath: logPath)
        }

        return pid
    }
}
