import ArcCore
import Foundation

/// Shared mutable state holder for watchers and processes.
///
/// Using an actor ensures thread-safe access to mutable state from async contexts.
public actor SharedState {
  public var config: ArcConfig
  private var processManager: ServerProcessManager

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
  ) throws -> pid_t {
    try processManager.startProcess(
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
  ) throws -> pid_t {
    try processManager.restartProcess(
      name: name,
      command: command,
      args: args,
      workingDir: workingDir,
      type: type,
      env: env
    )
  }

  /// Stops all managed processes.
  public func stopAll() {
    processManager.stopAll()
  }

  /// Starts cloudflared tunnel if enabled in configuration.
  ///
  /// - Parameter config: The Arc configuration.
  /// - Returns: The process ID if cloudflared was started, `nil` if disabled.
  /// - Throws: An error if cloudflared cannot be started or configuration is invalid.
  public func startCloudflared(config: ArcConfig) throws -> pid_t? {
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

    // Generate and write config file
    try CloudflaredConfigGenerator.writeConfig(config: config, tunnel: tunnel)

    // Start cloudflared process
    let baseDir = config.baseDir ?? FileManager.default.currentDirectoryPath
    let pid = try processManager.startProcess(
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
  public func stopCloudflared() {
    _ = processManager.stopProcess(name: "cloudflared")
  }

  /// Restarts cloudflared tunnel on configuration changes.
  ///
  /// - Parameter config: The Arc configuration.
  /// - Returns: The process ID if cloudflared was restarted, `nil` if disabled.
  /// - Throws: An error if cloudflared cannot be restarted or configuration is invalid.
  public func restartCloudflared(config: ArcConfig) throws -> pid_t? {
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

    // Generate and write config file
    try CloudflaredConfigGenerator.writeConfig(config: config, tunnel: tunnel)

    // Restart cloudflared process
    let baseDir = config.baseDir ?? FileManager.default.currentDirectoryPath
    let pid = try processManager.restartProcess(
      name: "cloudflared",
      command: cloudflaredPath,
      args: ["tunnel", "run"],
      workingDir: baseDir,
      type: .cloudflared,
      env: [:]
    )

    return pid
  }
}

