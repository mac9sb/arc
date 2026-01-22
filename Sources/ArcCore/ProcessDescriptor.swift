import Foundation

/// Metadata descriptor for an arc server process.
///
/// This struct contains all the information needed to identify and track
/// an arc server instance, including its PID, name, configuration,
/// and when it was started.
public struct ProcessDescriptor: Codable, Sendable {
    /// The unique process name (Docker-style, e.g., "mellow-falcon").
    public let name: String

    /// The process ID.
    public let pid: pid_t

    /// The proxy port the server is listening on.
    public let proxyPort: Int

    /// Path to the configuration file used.
    public let configPath: String

    /// When the process was started.
    public let startedAt: Date

    /// Creates a new process descriptor.
    public init(
        name: String,
        pid: pid_t,
        proxyPort: Int,
        configPath: String,
        startedAt: Date
    ) {
        self.name = name
        self.pid = pid
        self.proxyPort = proxyPort
        self.configPath = configPath
        self.startedAt = startedAt
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name, pid, proxyPort, configPath, startedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        let pidInt32 = try container.decode(Int32.self, forKey: .pid)
        self.pid = pid_t(pidInt32)
        self.proxyPort = try container.decode(Int.self, forKey: .proxyPort)
        self.configPath = try container.decode(String.self, forKey: .configPath)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(Int32(pid), forKey: .pid)
        try container.encode(proxyPort, forKey: .proxyPort)
        try container.encode(configPath, forKey: .configPath)
        try container.encode(startedAt, forKey: .startedAt)
    }
}

/// Process resource usage information.
public struct ProcessResourceUsage: Sendable {
    /// Process ID.
    public let pid: pid_t

    /// CPU usage as a percentage (0-100+).
    public let cpuPercent: Double

    /// Memory usage in megabytes.
    public let memoryMB: Double

    /// Command line of the process.
    public let command: String

    /// Creates a new resource usage struct.
    public init(
        pid: pid_t,
        cpuPercent: Double,
        memoryMB: Double,
        command: String
    ) {
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.command = command
    }
}

/// Manager for process descriptors.
///
/// Handles reading and writing process descriptor JSON files and PID files.
public actor ProcessDescriptorManager {
    /// The base directory for PID and descriptor files (typically `.pid`).
    private let baseDir: URL

    /// Creates a new descriptor manager.
    ///
    /// - Parameter baseDir: The base directory for PID files.
    public init(baseDir: URL) {
        self.baseDir = baseDir
    }

    /// Creates a new process descriptor for the current arc server.
    ///
    /// - Parameters:
    ///   - name: The process name.
    ///   - config: The arc configuration.
    ///   - configPath: Path to the config file.
    /// - Returns: The created descriptor.
    public func create(
        name: String,
        config: ArcConfig,
        configPath: String
    ) throws -> ProcessDescriptor {
        let pid = ProcessInfo.processInfo.processIdentifier

        let descriptor = ProcessDescriptor(
            name: name,
            pid: pid,
            proxyPort: config.proxyPort,
            configPath: configPath,
            startedAt: Date()
        )

        try writeDescriptor(descriptor)

        return descriptor
    }

    /// Reads a descriptor by process name.
    ///
    /// - Parameter name: The process name.
    /// - Returns: The descriptor, or nil if not found.
    public func read(name: String) throws -> ProcessDescriptor? {
        let path = descriptorPath(for: name)

        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(ProcessDescriptor.self, from: data)
    }

    /// Reads a descriptor by PID.
    ///
    /// - Parameter pid: The process ID.
    /// - Returns: The descriptor, or nil if not found.
    public func read(pid: pid_t) throws -> ProcessDescriptor? {
        let descriptors = try listAll()
        return descriptors.first { $0.pid == pid }
    }

    /// Lists all process descriptors.
    ///
    /// - Returns: Array of all descriptors.
    public func listAll() throws -> [ProcessDescriptor] {
        var descriptors: [ProcessDescriptor] = []

        guard
            let enumerator = FileManager.default.enumerator(
                at: baseDir,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }

        for case let file as URL in enumerator {
            if file.pathExtension == "json", file.lastPathComponent.hasPrefix("arc-") {
                do {
                    let data = try Data(contentsOf: file)
                    let descriptor = try JSONDecoder().decode(ProcessDescriptor.self, from: data)
                    descriptors.append(descriptor)
                } catch {
                    // Skip invalid files
                    continue
                }
            }
        }

        return descriptors.sorted { $0.startedAt < $1.startedAt }
    }

    /// Deletes a descriptor by process name.
    ///
    /// - Parameter name: The process name.
    public func delete(name: String) throws {
        let path = descriptorPath(for: name)

        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }

        let pidPath = pidPath(for: name)
        if FileManager.default.fileExists(atPath: pidPath.path) {
            try FileManager.default.removeItem(at: pidPath)
        }
    }

    /// Gets resource usage for a process.
    ///
    /// - Parameter pid: The process ID.
    /// - Returns: Resource usage information, or nil if the process doesn't exist.
    public func getResourceUsage(pid: pid_t) -> ProcessResourceUsage? {
        // Use ps to get process information
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(pid), "-o", "pid,%cpu,rss,command"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse output (skip header line)
            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count > 1 else { return nil }

            let parts = lines[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 3 else { return nil }

            guard let pid = pid_t(parts[0]),
                let cpuPercent = Double(parts[1]),
                let rssKb = Int(parts[2])
            else {
                return nil
            }

            // Command is the rest of the line
            let command = parts.dropFirst(3).joined(separator: " ")

            let memoryMB = Double(rssKb) / 1024.0

            return ProcessResourceUsage(
                pid: pid,
                cpuPercent: cpuPercent,
                memoryMB: memoryMB,
                command: command
            )
        } catch {
            return nil
        }
    }

    /// Cleans up stale descriptors (processes that are no longer running).
    ///
    /// - Returns: Array of removed descriptor names.
    public func cleanupStale() throws -> [String] {
        var removed: [String] = []

        for descriptor in try listAll() {
            let isRunning = kill(descriptor.pid, 0) == 0
            if !isRunning {
                try delete(name: descriptor.name)
                removed.append(descriptor.name)
            }
        }

        return removed
    }

    /// Writes a descriptor to disk.
    private func writeDescriptor(_ descriptor: ProcessDescriptor) throws {
        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: baseDir.path) {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }

        let path = descriptorPath(for: descriptor.name)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(descriptor)
        try data.write(to: path)

        // Also write PID file for backward compatibility with ServiceDetector
        let pidPath = pidPath(for: descriptor.name)
        try String(descriptor.pid).write(to: pidPath, atomically: true, encoding: .utf8)
    }

    /// Returns the path to a descriptor JSON file.
    private func descriptorPath(for name: String) -> URL {
        baseDir.appendingPathComponent("arc-\(name).json")
    }

    /// Returns the path to a PID file.
    private func pidPath(for name: String) -> URL {
        baseDir.appendingPathComponent("arc-\(name).pid")
    }
}
