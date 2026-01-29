import Darwin
import Foundation

/// Arc-specific errors.
public enum ArcError: Error, LocalizedError {
    case processFailed(command: String, exitCode: Int)
    case configLoadFailed(String)
    case invalidConfiguration(String)
    case processStartupFailed(name: String, message: String, logPath: String)

    public var errorDescription: String? {
        switch self {
        case .processFailed(let command, let exitCode):
            return "Process '\(command)' failed with exit code \(exitCode)"
        case .configLoadFailed(let message):
            return "Failed to load config: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .processStartupFailed(let name, let message, let logPath):
            return "Process '\(name)' failed to start: \(message)\nCheck logs at: \(logPath)"
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

        /// Whether the process was placed in its own process group (setpgid).
        /// When true, we kill the group via kill(-pid) to also stop child processes.
        public let useProcessGroup: Bool

        /// The type of process being managed.
        public enum ProcessType: Sendable {
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
        self.logDir = (config.logDir as NSString).expandingTildeInPath
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
    ) async throws -> pid_t {
        let task = Process()

        // Resolve working directory
        let resolvedWorkingDir: String
        if let wd = workingDir {
            resolvedWorkingDir = resolvePath(wd)
        } else {
            resolvedWorkingDir = config.baseDir ?? FileManager.default.currentDirectoryPath
        }

        // Resolve executable path relative to workingDir if provided, otherwise baseDir
        let resolvedCommand = resolveCommandPath(command, workingDir: resolvedWorkingDir)

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
        do {
            try ensureLogDirectoryExists()
        } catch {
            throw ArcError.invalidConfiguration(
                "Failed to create log directory at \(logDir): \(error.localizedDescription). "
                    + "Ensure the directory exists and is writable, or change logDir in ArcManifest.swift to a user-writable location.")
        }

        let logFileURL = URL(fileURLWithPath: logPath)

        // Create log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logPath) {
            guard FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil) else {
                throw ArcError.invalidConfiguration(
                    "Failed to create log file at \(logPath). Ensure the log directory is writable.")
            }
        }

        guard let outputHandle = try? FileHandle(forWritingTo: logFileURL),
            let errorHandle = try? FileHandle(forWritingTo: logFileURL)
        else {
            throw ArcError.invalidConfiguration(
                "Failed to open log file at \(logPath) for writing. Ensure the file is writable.")
        }

        task.standardOutput = outputHandle
        task.standardError = errorHandle

        try task.run()

        let pid = pid_t(task.processIdentifier)
        let useProcessGroup = (setpgid(pid, pid) == 0)
        processes[name] = ProcessRecord(
            pid: pid,
            name: name,
            type: type,
            startedAt: Date(),
            useProcessGroup: useProcessGroup
        )

        // Verify process is still running after a short delay
        // This catches immediate crashes (like missing env vars)
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

        guard ServiceDetector.isProcessRunning(pid: pid) else {
            // Process exited immediately - read error log
            var errorMessage = "Process exited immediately after startup"
            if let logContents = try? String(contentsOfFile: logPath, encoding: .utf8),
                !logContents.isEmpty
            {
                // Get last few lines of log for context
                let lines = logContents.components(separatedBy: .newlines)
                let lastLines = lines.suffix(5).joined(separator: "\n")
                if !lastLines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage += "\nLast log output:\n\(lastLines)"
                }
            }
            processes.removeValue(forKey: name)
            throw ArcError.processStartupFailed(name: name, message: errorMessage, logPath: logPath)
        }

        return pid
    }

    /// Stops a running process by name.
    ///
    /// Sends SIGTERM, waits 2 seconds, then SIGKILL if still running.
    /// - Parameter name: The name of the process to stop.
    /// - Returns: `true` if the process was found and stopped, `false` otherwise.
    @discardableResult
    public func stopProcess(name: String) -> Bool {
        guard let record = processes[name] else {
            return false
        }

        let pid = record.pid
        processes.removeValue(forKey: name)
        if record.useProcessGroup {
            ServiceDetector.killProcessGroupGracefully(pgid: pid, waitSeconds: 2)
        } else {
            ServiceDetector.killProcessGracefully(pid: pid, waitSeconds: 2)
        }
        return true
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

        guard ServiceDetector.isProcessRunning(pid: record.pid) else {
            processes.removeValue(forKey: name)
            return nil
        }
        return record
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
    ) async throws -> pid_t {
        stopProcess(name: name)
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        return try await startProcess(
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

    /// Resolves a command/executable path relative to workingDir if provided, otherwise baseDir.
    private func resolveCommandPath(_ command: String, workingDir: String) -> String {
        let expandedCommand = (command as NSString).expandingTildeInPath

        // If absolute path, use as-is
        if (expandedCommand as NSString).isAbsolutePath {
            return expandedCommand
        }

        // If relative path, resolve relative to workingDir (which is already resolved to absolute path)
        return (workingDir as NSString).appendingPathComponent(expandedCommand)
    }

    /// Ensures log directory exists.
    private func ensureLogDirectoryExists() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logDir) {
            try fileManager.createDirectory(
                atPath: logDir,
                withIntermediateDirectories: true
            )
        }
    }
}
