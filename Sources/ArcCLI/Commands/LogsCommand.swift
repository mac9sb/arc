import ArcCore
import ArgumentParser
import Foundation
import Noora
import PklSwift

/// Command to view Arc server logs.
///
/// Displays log file contents, with optional follow mode for real-time
/// log streaming.
///
/// ## Usage
///
/// ```bash
/// arc logs                # Show last 50 lines of logs
/// arc logs --follow       # Follow log output (like tail -f)
/// ```
struct LogsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "logs",
    abstract: "Show arc server logs"
  )

  /// Path to the Pkl configuration file.
  ///
  /// Defaults to `pkl/config.pkl` in the current directory.
  @Option(name: .shortAndLong, help: "Path to config file")
  var config: String = "pkl/config.pkl"

  /// Whether to follow log output in real-time.
  ///
  /// When enabled, continuously displays new log entries as they are written,
  /// similar to `tail -f`.
  @Flag(name: .long, help: "Follow log output")
  var follow: Bool = false

  /// Executes the logs command.
  ///
  /// Reads and displays log file contents. In follow mode, streams new
  /// log entries as they are written.
  ///
  /// - Throws: An error if the log file cannot be read.
  func run() async throws {
    let configURL = URL(fileURLWithPath: config)

    guard
      let config = try? await ArcConfig.loadFrom(
        source: ModuleSource.path(config),
        configPath: configURL
      )
    else {
      Noora().warning("Could not load configuration: invalid config file")
      return
    }

    let logPath = "\(config.logDir)/arc.log"

    if !FileManager.default.fileExists(atPath: logPath) {
      Noora().warning("Log file not found")
      return
    }

    if follow {
      let tailProcess = Process()
      tailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
      tailProcess.arguments = ["-f", logPath]
      tailProcess.standardOutput = FileHandle.standardOutput
      tailProcess.standardError = FileHandle.standardError
      try tailProcess.run()
      tailProcess.waitUntilExit()
    } else {
      let content = try String(contentsOfFile: logPath, encoding: .utf8)
      let lines = content.components(separatedBy: "\n")
      let lastLines = Array(lines.suffix(50))

      Noora().info("Log file: \(logPath)")
      print(lastLines.joined(separator: "\n"))
    }
  }
}
