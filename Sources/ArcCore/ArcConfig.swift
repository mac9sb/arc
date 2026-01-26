// Code generated from Pkl module `dev.personal.ArcConfig`.
// This file defines the Swift types for Arc configuration.

import Foundation
import PklSwift

// MARK: - ArcConfig

/// Arc configuration for local development.
public struct ArcConfig: Decodable, Hashable, Sendable {
    /// Port the proxy server listens on.
    public var proxyPort: Int

    /// Directory for log files.
    public var logDir: String

    /// Base directory for all projects.
    /// If not specified, inferred as directory containing config file.
    public var baseDir: String?

    /// Health check interval in seconds.
    public var healthCheckInterval: Int

    /// Server version displayed in dashboard.
    public var version: String

    /// Deployment region identifier displayed in dashboard.
    public var region: String?

    /// Optional process name for this arc instance.
    /// If nil, a Docker-style random name will be generated at runtime.
    public var processName: String?

    /// Unified list of sites (static and apps).
    public var sites: [Site]

    /// Cloudflare Tunnel configuration.
    public var cloudflare: CloudflareTunnel?

    /// SSH configuration.
    public var ssh: SshConfig?

    /// Global watch configuration.
    public var watch: WatchConfig?

    public init(
        proxyPort: Int = 8080,
        logDir: String = "~/Library/Logs/arc",
        baseDir: String? = nil,
        healthCheckInterval: Int = 30,
        version: String = "V.2.0.0",
        region: String? = nil,
        sites: [Site] = [],
        cloudflare: CloudflareTunnel? = nil,
        ssh: SshConfig? = nil,
        watch: WatchConfig? = nil,
        processName: String? = nil
    ) {
        self.proxyPort = proxyPort
        self.logDir = logDir
        self.baseDir = baseDir
        self.healthCheckInterval = healthCheckInterval
        self.version = version
        self.region = region
        self.sites = sites
        self.cloudflare = cloudflare
        self.ssh = ssh
        self.watch = watch
        self.processName = processName
    }
}

// MARK: - Site (Discriminated Union)

/// Unified site configuration with discriminator.
public enum Site: Hashable, Sendable, Identifiable {
    case `static`(StaticSite)
    case app(AppSite)

    public var id: String {
        switch self {
        case .static(let site): return site.name
        case .app(let site): return site.name
        }
    }

    public var name: String {
        switch self {
        case .static(let site): return site.name
        case .app(let site): return site.name
        }
    }

    public var domain: String {
        switch self {
        case .static(let site): return site.domain
        case .app(let site): return site.domain
        }
    }

    public var watchTargets: [String]? {
        switch self {
        case .static(let site): return site.watchTargets
        case .app(let site): return site.watchTargets
        }
    }
}

extension Site: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)

        switch kind {
        case "static":
            self = .static(try StaticSite(from: decoder))
        case "app":
            self = .app(try AppSite(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid site kind: \(kind)"
            )
        }
    }
}

// MARK: - StaticSite

/// Static site configuration.
public struct StaticSite: Decodable, Hashable, Sendable {
    /// Unique identifier for this site.
    public var name: String

    /// Domain to match for routing.
    public var domain: String

    /// Path to the output directory relative to `baseDir`.
    public var outputPath: String

    /// Watch targets override (optional).
    public var watchTargets: [String]?

    public init(
        name: String,
        domain: String,
        outputPath: String,
        watchTargets: [String]? = nil
    ) {
        self.name = name
        self.domain = domain
        self.outputPath = outputPath
        self.watchTargets = watchTargets
    }
}

// MARK: - AppSite

/// App site configuration.
public struct AppSite: Decodable, Hashable, Sendable {
    /// Unique identifier for this site.
    public var name: String

    /// Domain to match for routing.
    public var domain: String

    /// Port the application listens on.
    public var port: Int

    /// Health check endpoint path.
    public var healthPath: String

    /// Process configuration.
    public var process: ProcessConfig

    /// Watch targets override (optional).
    public var watchTargets: [String]?

    public init(
        name: String,
        domain: String,
        port: Int,
        healthPath: String = "/health",
        process: ProcessConfig,
        watchTargets: [String]? = nil
    ) {
        self.name = name
        self.domain = domain
        self.port = port
        self.healthPath = healthPath
        self.process = process
        self.watchTargets = watchTargets
    }

    /// Returns the full URL for health checks.
    public func healthURL() -> URL? {
        URL(string: "http://127.0.0.1:\(port)\(healthPath)")
    }

    /// Returns the base URL for the application.
    public func baseURL() -> URL? {
        URL(string: "http://127.0.0.1:\(port)")
    }
}

// MARK: - ProcessConfig

/// Process configuration for app sites.
public struct ProcessConfig: Decodable, Hashable, Sendable {
    /// Working directory relative to `baseDir`.
    public var workingDir: String

    /// Path to executable (relative to workingDir or absolute).
    public var executable: String?

    /// Command to run (alternative to executable).
    public var command: String?

    /// Arguments for command.
    public var args: [String]?

    /// Environment variables.
    public var env: [String: String]?

    public init(
        workingDir: String,
        executable: String? = nil,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil
    ) {
        self.workingDir = workingDir
        self.executable = executable
        self.command = command
        self.args = args
        self.env = env
    }
}

// MARK: - WatchConfig

/// Global watch configuration.
public struct WatchConfig: Decodable, Hashable, Sendable {
    /// Whether to watch config.pkl for changes.
    public var watchConfigPkl: Bool

    /// Whether to follow symlinks when watching.
    public var followSymlinks: Bool

    /// Debounce interval in milliseconds.
    public var debounceMs: Int

    /// Cooldown period in milliseconds after restart.
    public var cooldownMs: Int

    public init(
        watchConfigPkl: Bool = true,
        followSymlinks: Bool = false,
        debounceMs: Int = 300,
        cooldownMs: Int = 1000
    ) {
        self.watchConfigPkl = watchConfigPkl
        self.followSymlinks = followSymlinks
        self.debounceMs = debounceMs
        self.cooldownMs = cooldownMs
    }
}

// MARK: - CloudflareTunnel

/// Cloudflare Tunnel configuration.
public struct CloudflareTunnel: Decodable, Hashable, Sendable {
    /// Whether to enable the Cloudflare Tunnel.
    public var enabled: Bool

    /// Path to cloudflared executable.
    public var cloudflaredPath: String

    /// Tunnel name or ID.
    public var tunnelName: String?

    /// Tunnel UUID (optional).
    public var tunnelUUID: String?

    public init(
        enabled: Bool = false,
        cloudflaredPath: String = "/opt/homebrew/bin/cloudflared",
        tunnelName: String? = nil,
        tunnelUUID: String? = nil
    ) {
        self.enabled = enabled
        self.cloudflaredPath = cloudflaredPath
        self.tunnelName = tunnelName
        self.tunnelUUID = tunnelUUID
    }
}

// MARK: - SshConfig

/// SSH configuration for Cloudflare tunnel access.
public struct SshConfig: Decodable, Hashable, Sendable {
    /// Whether to enable SSH access via Cloudflare tunnel.
    public var enabled: Bool

    /// Domain for SSH access via Cloudflare tunnel.
    public var domain: String?

    /// Local SSH port to forward.
    public var port: Int

    public init(
        enabled: Bool = false,
        domain: String? = nil,
        port: Int = 22
    ) {
        self.enabled = enabled
        self.domain = domain
        self.port = port
    }
}

// MARK: - Module Loading

extension ArcConfig {
    /// Finds ArcConfiguration.pkl in the bundle resources.
    ///
    /// - Returns: Path to ArcConfiguration.pkl if found, nil otherwise.
    private static func findArcConfigurationPkl() -> String? {
        let fileManager = FileManager.default
        
        // Try to find Resources directory relative to the executable
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let executableURL = URL(fileURLWithPath: executablePath)
        let executableDir = executableURL.deletingLastPathComponent()
        
        // Try bundle path - file is directly in the bundle (not in Resources subdirectory)
        var bundleURL = executableDir.appendingPathComponent("Arc_ArcCLI.bundle")
        var arcConfigPath = bundleURL.appendingPathComponent("ArcConfiguration.pkl").path
        
        if fileManager.fileExists(atPath: arcConfigPath) {
            return arcConfigPath
        }
        
        // Try bundle/Resources path (for some installation methods)
        bundleURL = executableDir.appendingPathComponent("Arc_ArcCLI.bundle").appendingPathComponent("Resources")
        arcConfigPath = bundleURL.appendingPathComponent("ArcConfiguration.pkl").path
        
        if fileManager.fileExists(atPath: arcConfigPath) {
            return arcConfigPath
        }
        
        // Try Resources directory next to executable
        let resourcesURL = executableDir.appendingPathComponent("Resources")
        arcConfigPath = resourcesURL.appendingPathComponent("ArcConfiguration.pkl").path
        
        if fileManager.fileExists(atPath: arcConfigPath) {
            return arcConfigPath
        }

        // Try relative to Sources/ArcCLI (for development)
        // Look for the Resources directory relative to where we might be running from
        let currentFile = #file
        let currentFileURL = URL(fileURLWithPath: currentFile)
        // Go up from ArcConfig.swift -> ArcCore -> Sources -> tooling/arc -> Sources -> ArcCLI -> Resources
        let devResourcesURL = currentFileURL
            .deletingLastPathComponent()  // ArcCore
            .deletingLastPathComponent()  // Sources
            .appendingPathComponent("ArcCLI")
            .appendingPathComponent("Resources")
        arcConfigPath = devResourcesURL.appendingPathComponent("ArcConfiguration.pkl").path
        
        if fileManager.fileExists(atPath: arcConfigPath) {
            return arcConfigPath
        }

        return nil
    }

    /// Ensures ArcConfiguration.pkl is available in the config directory for Pkl module resolution.
    ///
    /// - Parameter configDir: Directory containing the config file.
    /// - Returns: Path to ArcConfiguration.pkl (either existing or copied).
    /// - Throws: An error if ArcConfiguration.pkl cannot be found or copied.
    private static func ensureArcConfigurationPkl(in configDir: String) throws -> String {
        let fileManager = FileManager.default
        let targetPath = (configDir as NSString).appendingPathComponent("ArcConfiguration.pkl")
        
        // If it already exists in the config directory, use it
        if fileManager.fileExists(atPath: targetPath) {
            return targetPath
        }
        
        // Try to find it in the bundle
        guard let sourcePath = findArcConfigurationPkl() else {
            throw ArcError.invalidConfiguration("Cannot find ArcConfiguration.pkl in bundle resources")
        }
        
        // Copy it to the config directory so Pkl can resolve it
        try fileManager.copyItem(atPath: sourcePath, toPath: targetPath)
        
        return targetPath
    }

    /// Loads the Arc configuration from a Pkl source.
    ///
    /// - Parameter source: The Pkl module source to load from.
    /// - Returns: The loaded configuration.
    /// - Throws: An error if loading or parsing fails.
    public static func loadFrom(source: ModuleSource) async throws -> ArcConfig {
        try await PklSwift.withEvaluator { evaluator in
            try await evaluator.evaluateModule(source: source, as: ArcConfig.self)
        }
    }

    /// Loads the Arc configuration from a Pkl source, with optional baseDir inference.
    ///
    /// If the loaded config doesn't specify a baseDir, it's inferred as the directory
    /// containing the config file.
    ///
    /// - Parameters:
    ///   - source: The Pkl module source to load from.
    ///   - configPath: Optional explicit path to config file (for baseDir inference).
    /// - Returns: The loaded configuration, with baseDir inferred if needed.
    /// - Throws: An error if loading or parsing fails.
    public static func loadFrom(
        source: ModuleSource,
        configPath: URL? = nil
    ) async throws -> ArcConfig {
        // Ensure ArcConfiguration.pkl is available for module resolution
        if let configPath = configPath {
            let configDir = configPath.deletingLastPathComponent().path
            _ = try ensureArcConfigurationPkl(in: configDir)
        }
        
        var config = try await PklSwift.withEvaluator { evaluator in
            try await evaluator.evaluateModule(source: source, as: ArcConfig.self)
        }

        // Infer baseDir if not specified
        if config.baseDir == nil, let configPath = configPath {
            config.baseDir = configPath.deletingLastPathComponent().path
        }

        return config
    }
}
