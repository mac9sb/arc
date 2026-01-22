import ArcCore
import ArgumentParser
import Foundation
import Noora
import PklSwift

struct LogsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "logs",
    abstract: "Show arc server logs"
  )

  @Option(name: .shortAndLong, help: "Path to config file")
  var config: String = "pkl/config.pkl"

  @Flag(name: .long, help: "Follow log output")
  var follow: Bool = false

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
