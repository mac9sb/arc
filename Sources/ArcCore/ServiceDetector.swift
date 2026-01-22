import Foundation

/// Portable service detection using PID and lock files.
public struct ServiceDetector {

  /// Information about a detected service.
  public struct ServiceInfo {
    /// The process identifier.
    public let pid: Int32
    
    /// The PID file URL, if found.
    public let pidFile: URL?
    
    /// The lock file URL, if found.
    public let lockFile: URL?
    
    /// Whether the process is currently running.
    public let isRunning: Bool

    /// Creates a new service info instance.
    ///
    /// - Parameters:
    ///   - pid: The process identifier.
    ///   - pidFile: The PID file URL. Defaults to `nil`.
    ///   - lockFile: The lock file URL. Defaults to `nil`.
    ///   - isRunning: Whether the process is running.
    public init(pid: Int32, pidFile: URL? = nil, lockFile: URL? = nil, isRunning: Bool) {
      self.pid = pid
      self.pidFile = pidFile
      self.lockFile = lockFile
      self.isRunning = isRunning
    }
  }

  private let baseDir: URL

  /// Creates a new service detector.
  ///
  /// - Parameter baseDir: The base directory to search for PID and lock files.
  public init(baseDir: URL) {
    self.baseDir = baseDir
  }

  /// Detects a service by checking common PID/lock file locations.
  ///
  /// - Parameter serviceName: The name of the service to detect.
  /// - Returns: ServiceInfo if detected, nil otherwise.
  public func detectService(named serviceName: String) -> ServiceInfo? {
    // Check common PID file locations
    let pidLocations = [
      baseDir.appendingPathComponent(".pid/\(serviceName).pid"),
      baseDir.appendingPathComponent("var/run/\(serviceName).pid"),
      baseDir.appendingPathComponent("\(serviceName).pid"),
    ]

    for pidFile in pidLocations {
      if let info = checkPIDFile(pidFile) {
        return info
      }
    }

    // Check lock files
    let lockLocations = [
      baseDir.appendingPathComponent(".lock/\(serviceName).lock"),
      baseDir.appendingPathComponent("var/lock/\(serviceName).lock"),
      baseDir.appendingPathComponent("\(serviceName).lock"),
    ]

    for lockFile in lockLocations {
      if let info = checkLockFile(lockFile) {
        return info
      }
    }

    return nil
  }

  /// Checks a PID file for service information.
  private func checkPIDFile(_ pidFile: URL) -> ServiceInfo? {
    guard FileManager.default.fileExists(atPath: pidFile.path) else {
      return nil
    }

    do {
      let pidString = try String(contentsOf: pidFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      guard let pid = Int32(pidString) else {
        return nil
      }

      let isRunning = isProcessRunning(pid)
      return ServiceInfo(pid: pid, pidFile: pidFile, lockFile: nil, isRunning: isRunning)
    } catch {
      return nil
    }
  }

  /// Checks a lock file for service information.
  private func checkLockFile(_ lockFile: URL) -> ServiceInfo? {
    guard FileManager.default.fileExists(atPath: lockFile.path) else {
      return nil
    }

    // Try to read PID from lock file (common format: first line is PID)
    do {
      let content = try String(contentsOf: lockFile, encoding: .utf8)
      let lines = content.components(separatedBy: .newlines)

      guard let firstLine = lines.first,
        let pid = Int32(firstLine.trimmingCharacters(in: .whitespacesAndNewlines))
      else {
        return nil
      }

      let isRunning = isProcessRunning(pid)
      return ServiceInfo(pid: pid, pidFile: nil, lockFile: lockFile, isRunning: isRunning)
    } catch {
      return nil
    }
  }

  /// Checks if a process is running.
  private func isProcessRunning(_ pid: Int32) -> Bool {
    // On macOS/Unix, sending signal 0 checks if process exists
    return kill(pid, 0) == 0
  }

  /// Checks if a process is currently running.
  ///
  /// On macOS and Unix systems, this uses `kill(pid, 0)` to check if the process exists.
  ///
  /// - Parameter pid: The process identifier to check.
  /// - Returns: `true` if the process is running, `false` otherwise.
  public static func isProcessRunning(pid: Int32) -> Bool {
    // On macOS/Unix, sending signal 0 checks if process exists
    return kill(pid, 0) == 0
  }

  /// Signals that can be sent to a process.
  public enum Signal {
    /// SIGTERM - requests graceful termination.
    case term
    /// SIGKILL - forces immediate termination.
    case kill
  }

  /// Sends a signal to a process.
  ///
  /// - Parameters:
  ///   - pid: The process ID.
  ///   - signal: The signal to send.
  /// - Returns: true if signal was sent successfully.
  public static func killProcess(pid: Int32, signal: Signal) -> Bool {
    let sig: Int32
    switch signal {
    case .term: sig = SIGTERM
    case .kill: sig = SIGKILL
    }

    return kill(pid, sig) == 0
  }

  /// Writes a PID file for a service.
  ///
  /// - Parameters:
  ///   - pid: The process ID to write.
  ///   - serviceName: The name of the service.
  /// - Returns: The URL of the created PID file, or nil if failed.
  @discardableResult
  public func writePIDFile(pid: Int32, serviceName: String) -> URL? {
    let pidDir = baseDir.appendingPathComponent(".pid")

    // Create PID directory if needed
    try? FileManager.default.createDirectory(
      at: pidDir,
      withIntermediateDirectories: true
    )

    let pidFile = pidDir.appendingPathComponent("\(serviceName).pid")

    do {
      try String(pid).write(to: pidFile, atomically: true, encoding: .utf8)
      return pidFile
    } catch {
      return nil
    }
  }

  /// Removes a PID file for a service.
  ///
  /// - Parameter serviceName: The name of the service.
  public func removePIDFile(serviceName: String) {
    let pidFile = baseDir.appendingPathComponent(".pid/\(serviceName).pid")
    try? FileManager.default.removeItem(at: pidFile)
  }

  /// Gets PID listening on a specific port using lsof.
  ///
  /// - Parameter port: The port number.
  /// - Returns: The PID if found, nil otherwise.
  public static func getPIDForPort(_ port: Int) -> Int32? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    task.arguments = ["-ti", ":\(port)"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()  // Suppress errors

    do {
      try task.run()
      task.waitUntilExit()

      guard task.terminationStatus == 0 else {
        return nil
      }

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      guard
        let output = String(data: data, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !output.isEmpty,
        let pid = Int32(output.components(separatedBy: .newlines).first ?? "")
      else {
        return nil
      }

      return pid
    } catch {
      return nil
    }
  }
}
