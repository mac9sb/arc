import Foundation

/// Arc-specific errors.
public enum ArcError: Error, LocalizedError {
  case processFailed(command: String, exitCode: Int)
  case configLoadFailed(String)
  case invalidConfiguration(String)

  public var errorDescription: String? {
    switch self {
    case .processFailed(let command, let exitCode):
      return "Process '\(command)' failed with exit code \(exitCode)"
    case .configLoadFailed(let message):
      return "Failed to load config: \(message)"
    case .invalidConfiguration(let message):
      return "Invalid configuration: \(message)"
    }
  }
}

/// Manages server and app site processes with foreground and background support.
///
/// `ServerProcessManager` handles the lifecycle of processes for sites and services,
/// including starting, stopping, and restarting processes with proper logging and
/// environment configuration.
public class ServerProcessManager {
  /// Information about a managed process.
  public struct ProcessRecord {
    /// The process identifier.
    public let pid: pid_t
    
    /// The process name.
    public let name: String
    
    /// The process type.
    public let type: ProcessType
    
    /// When the process was started.
    public let startedAt: Date

    /// The type of process being managed.
    public enum ProcessType {
      /// A server process.
      case server
      /// A static site process.
      case staticSite
      /// An application process.
      case app
      /// A cloudflared tunnel process.
      case cloudflared
    }
  }

  private var processes: [String: ProcessRecord] = [:]
  private let config: ArcConfig
  private let logDir: String

  /// Creates a new process manager.
  ///
  /// - Parameter config: The Arc configuration to use.
  public init(config: ArcConfig) {
    self.config = config
    self.logDir = config.logDir
  }

  /// Starts a process for a site or main server.
  ///
  /// - Parameters:
  ///   - name: A unique name for the process.
  ///   - command: The command or executable path to run.
  ///   - args: Command-line arguments. Defaults to an empty array.
  ///   - workingDir: The working directory. If `nil`, uses the config's base directory.
  ///   - type: The type of process being started.
  ///   - env: Additional environment variables. Defaults to an empty dictionary.
  /// - Returns: The process identifier of the started process.
  /// - Throws: An error if the process cannot be started.
  @discardableResult
  public func startProcess(
    name: String,
    command: String,
    args: [String] = [],
    workingDir: String? = nil,
    type: ProcessRecord.ProcessType,
    env: [String: String] = [:]
  ) throws -> pid_t {
    let task = Process()

    // Resolve working directory
    let resolvedWorkingDir: String
    if let wd = workingDir {
      resolvedWorkingDir = resolvePath(wd)
    } else {
      resolvedWorkingDir = config.baseDir ?? FileManager.default.currentDirectoryPath
    }

    // Resolve executable path
    let resolvedCommand = resolvePath(command)

    task.executableURL = URL(fileURLWithPath: resolvedCommand)
    task.arguments = args
    task.currentDirectoryURL = URL(fileURLWithPath: resolvedWorkingDir)

    // Set up environment
    var environment = Foundation.ProcessInfo.processInfo.environment
    for (key, value) in env {
      environment[key] = value
    }
    task.environment = environment

    // Set up log redirection
    let logPath = "\(logDir)/\(name).log"
    ensureLogDirectoryExists()

    let logFileURL = URL(fileURLWithPath: logPath)
    task.standardOutput = try? FileHandle(forWritingTo: logFileURL)
    task.standardError = try? FileHandle(forWritingTo: logFileURL)

    try task.run()

    let pid = pid_t(task.processIdentifier)
    processes[name] = ProcessRecord(
      pid: pid,
      name: name,
      type: type,
      startedAt: Date()
    )

    return pid
  }

  /// Stops a running process by name.
  ///
  /// - Parameter name: The name of the process to stop.
  /// - Returns: `true` if the process was found and stopped, `false` otherwise.
  @discardableResult
  public func stopProcess(name: String) -> Bool {
    guard let record = processes[name] else {
      return false
    }

    let success = ServiceDetector.killProcess(pid: record.pid, signal: .term)
    if success {
      processes.removeValue(forKey: name)
    }

    return success
  }

  /// Stops all managed processes.
  public func stopAll() {
    let names = Array(processes.keys)
    for name in names {
      stopProcess(name: name)
    }
  }

  /// Gets information about a running process.
  ///
  /// - Parameter name: The name of the process.
  /// - Returns: The process record if found and running, `nil` otherwise.
  public func getProcess(name: String) -> ProcessRecord? {
    guard let record = processes[name] else { return nil }

    if ServiceDetector.isProcessRunning(pid: record.pid) {
      return record
    } else {
      processes.removeValue(forKey: name)
      return nil
    }
  }

  /// Gets all currently running processes.
  ///
  /// Dead processes are automatically removed from the internal tracking.
  ///
  /// - Returns: An array of all running process records.
  public func getAllProcesses() -> [ProcessRecord] {
    let deadProcesses = processes.filter { name, record in
      !ServiceDetector.isProcessRunning(pid: record.pid)
    }

    for name in deadProcesses.keys {
      processes.removeValue(forKey: name)
    }

    return Array(processes.values)
  }

  /// Restarts a process by stopping it and starting it again.
  ///
  /// - Parameters:
  ///   - name: The name of the process to restart.
  ///   - command: The command or executable path to run.
  ///   - args: Command-line arguments. Defaults to an empty array.
  ///   - workingDir: The working directory. If `nil`, uses the config's base directory.
  ///   - type: The type of process being restarted.
  ///   - env: Additional environment variables. Defaults to an empty dictionary.
  /// - Returns: The process identifier of the restarted process.
  /// - Throws: An error if the process cannot be restarted.
  public func restartProcess(
    name: String,
    command: String,
    args: [String] = [],
    workingDir: String? = nil,
    type: ProcessRecord.ProcessType,
    env: [String: String] = [:]
  ) throws -> pid_t {
    stopProcess(name: name)
    Thread.sleep(forTimeInterval: 0.5)
    return try startProcess(
      name: name,
      command: command,
      args: args,
      workingDir: workingDir,
      type: type,
      env: env
    )
  }

  /// Runs a process in the foreground with stdout/stderr passthrough.
  ///
  /// Unlike `startProcess`, this method waits for the process to complete and
  /// passes output directly to the current process's stdout/stderr.
  ///
  /// - Parameters:
  ///   - command: The command or executable path to run.
  ///   - args: Command-line arguments. Defaults to an empty array.
  ///   - workingDir: The working directory. If `nil`, uses the config's base directory.
  ///   - env: Additional environment variables. Defaults to an empty dictionary.
  /// - Throws: An error if the process fails or exits with a non-zero status.
  public func runForeground(
    command: String,
    args: [String] = [],
    workingDir: String? = nil,
    env: [String: String] = [:]
  ) throws {
    let task = Process()

    let resolvedWorkingDir: String
    if let wd = workingDir {
      resolvedWorkingDir = resolvePath(wd)
    } else {
      resolvedWorkingDir = config.baseDir ?? FileManager.default.currentDirectoryPath
    }

    let resolvedCommand = resolvePath(command)

    task.executableURL = URL(fileURLWithPath: resolvedCommand)
    task.arguments = args
    task.currentDirectoryURL = URL(fileURLWithPath: resolvedWorkingDir)

    var environment = Foundation.ProcessInfo.processInfo.environment
    for (key, value) in env {
      environment[key] = value
    }
    task.environment = environment

    // Passthrough stdout/stderr
    task.standardOutput = FileHandle.standardOutput
    task.standardError = FileHandle.standardError

    try task.run()
    task.waitUntilExit()

    if task.terminationStatus != 0 {
      throw ArcError.processFailed(
        command: command,
        exitCode: Int(task.terminationStatus)
      )
    }
  }

  /// Resolves a path relative to baseDir.
  private func resolvePath(_ path: String) -> String {
    let path = (path as NSString).expandingTildeInPath

    if (path as NSString).isAbsolutePath {
      return path
    }

    guard let baseDir = config.baseDir else {
      return path
    }

    return "\(baseDir)/\(path)"
  }

  /// Ensures log directory exists.
  private func ensureLogDirectoryExists() {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: logDir) {
      try? fileManager.createDirectory(
        atPath: logDir,
        withIntermediateDirectories: true
      )
    }
  }
}
