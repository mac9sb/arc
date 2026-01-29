import Foundation

// MARK: - ArcConfiguration

/// Top-level Swift manifest configuration for Arc.
///
/// This is the main configuration object that defines your entire Arc setup.
/// Create an instance of this in your `Arc.swift` file.
///
/// ## Example
///
/// ```swift
/// import ArcDescription
///
/// let config = ArcConfiguration(
///     processName: "my-server",
///     sites: .init(
///         services: [
///             .init(name: "api", domain: "api.local", port: 8000,
///                   process: .init(workingDir: "apps/api/", executable: ".build/release/API"))
///         ],
///         pages: [
///             .init(name: "site", domain: "site.local", outputPath: "static/.output")
///         ]
///     )
/// )
/// ```
///
/// ## Topics
///
/// ### Configuration Properties
///
/// - ``proxyPort``
/// - ``logDir``
/// - ``baseDir``
/// - ``healthCheckInterval``
/// - ``version``
/// - ``region``
/// - ``processName``
///
/// ### Site Configuration
///
/// - ``sites``
/// - ``Sites``
/// - ``ServiceSite``
/// - ``StaticSite``
///
/// ### Optional Features
///
/// - ``cloudflare``
/// - ``ssh``
/// - ``watch``
///
/// ## See Also
///
/// - <doc:Examples>
/// - <doc:Configuration>
public struct ArcConfiguration: Codable, Sendable, Hashable {
    /// Port the proxy server listens on.
    ///
    /// This is the port Arc's reverse proxy will bind to. All incoming HTTP requests
    /// will be routed through this port.
    ///
    /// - Note: Default is `8080`
    /// - Precondition: Must be in range 1-65535
    public var proxyPort: Int

    /// Directory for log files.
    ///
    /// Arc writes logs for itself and each service to this directory.
    /// Tilde (`~`) is expanded to the user's home directory.
    ///
    /// - Note: Default is `~/Library/Logs/arc`
    /// - Precondition: Cannot be empty
    public var logDir: String

    /// Base directory for all projects.
    ///
    /// All relative paths in service and static site configurations are resolved
    /// relative to this directory. If `nil`, defaults to the directory containing
    /// `Arc.swift`.
    ///
    /// - Note: Auto-detected from manifest location if not specified
    public var baseDir: String?

    /// Health check interval in seconds.
    ///
    /// How often Arc checks if services are responding to health check requests.
    ///
    /// - Note: Default is `30` seconds
    /// - Precondition: Must be positive
    public var healthCheckInterval: Int

    /// Server version displayed in status.
    ///
    /// Informational string shown in `arc status` output.
    ///
    /// - Note: Default is `"V.2.0.0"`
    public var version: String

    /// Deployment region identifier displayed in status.
    ///
    /// Optional identifier for the deployment region (e.g., "us-west-2", "eu-central-1").
    public var region: String?

    /// Optional process name for this arc instance.
    ///
    /// Used to identify this Arc instance when multiple instances are running.
    public var processName: String?

    /// Site groups.
    ///
    /// Contains both backend services and static pages to be served by Arc.
    ///
    /// ## See Also
    ///
    /// - ``Sites``
    /// - ``ServiceSite``
    /// - ``StaticSite``
    public var sites: Sites

    /// Optional extensions/modules.
    ///
    /// Groups optional integrations like Cloudflare tunnels and SSH.
    ///
    /// ## See Also
    ///
    /// - ``Extensions``
    public var extensions: Extensions?

    /// Global watch configuration.
    ///
    /// Controls file watching and hot-reload behavior.
    ///
    /// ## See Also
    ///
    /// - ``WatchConfig``
    public var watch: WatchConfig

    /// Cloudflare Tunnel configuration.
    ///
    /// **Deprecated**: Use `extensions.cloudflare` instead.
    @available(*, deprecated, renamed: "extensions.cloudflare")
    public var cloudflare: CloudflareConfig? {
        get { extensions?.cloudflare }
        set {
            if extensions == nil {
                extensions = Extensions()
            }
            extensions?.cloudflare = newValue
        }
    }

    /// SSH configuration.
    ///
    /// **Deprecated**: Use `extensions.ssh` instead.
    @available(*, deprecated, renamed: "extensions.ssh")
    public var ssh: SshConfig? {
        get { extensions?.ssh }
        set {
            if extensions == nil {
                extensions = Extensions()
            }
            extensions?.ssh = newValue
        }
    }

    public init(
        proxyPort: Int = 8080,
        logDir: String = "~/Library/Logs/arc",
        baseDir: String? = nil,
        healthCheckInterval: Int = 30,
        version: String = "V.2.0.0",
        region: String? = nil,
        processName: String? = nil,
        sites: Sites = Sites(),
        watch: WatchConfig = WatchConfig(),
        extensions: Extensions? = nil,
        cloudflare: CloudflareConfig? = nil,
        ssh: SshConfig? = nil
    ) {
        // Validate proxy port
        precondition(proxyPort > 0 && proxyPort < 65536, "Proxy port must be in range 1-65535, got \(proxyPort)")

        // Validate health check interval
        precondition(healthCheckInterval > 0, "Health check interval must be positive, got \(healthCheckInterval)")

        // Validate log directory
        precondition(!logDir.isEmpty, "Log directory cannot be empty")

        // Validate unique site names across all sites
        let allSiteNames = sites.services.map(\.name) + sites.pages.map(\.name)
        let uniqueNames = Set(allSiteNames)
        precondition(
            allSiteNames.count == uniqueNames.count,
            "Site names must be unique. Duplicate names found: \(allSiteNames.filter { name in allSiteNames.filter { $0 == name }.count > 1 }.uniqued())"
        )

        // Validate unique ports across all services
        let servicePorts = sites.services.map(\.port)
        let uniquePorts = Set(servicePorts)
        precondition(
            servicePorts.count == uniquePorts.count,
            "Service ports must be unique. Duplicate ports found: \(servicePorts.filter { port in servicePorts.filter { $0 == port }.count > 1 }.uniqued())"
        )

        self.proxyPort = proxyPort
        self.logDir = logDir
        self.baseDir = baseDir
        self.healthCheckInterval = healthCheckInterval
        self.version = version
        self.region = region
        self.processName = processName
        self.sites = sites
        self.watch = watch

        // Handle both new and deprecated APIs
        if let extensions = extensions {
            self.extensions = extensions
        } else if cloudflare != nil || ssh != nil {
            self.extensions = Extensions(cloudflare: cloudflare, ssh: ssh)
        } else {
            self.extensions = nil
        }
    }
}

// MARK: - Array Extension for Validation

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Extensions

/// Optional extensions and integrations.
///
/// Groups optional modules like Cloudflare tunnels and SSH configuration.
public struct Extensions: Codable, Sendable, Hashable {
    /// Cloudflare Tunnel configuration.
    ///
    /// Optional Cloudflare Tunnel integration for exposing local services.
    ///
    /// ## See Also
    ///
    /// - ``CloudflareConfig``
    public var cloudflare: CloudflareConfig?

    /// SSH configuration.
    ///
    /// Optional SSH access configuration via Cloudflare tunnel.
    ///
    /// ## See Also
    ///
    /// - ``SshConfig``
    public var ssh: SshConfig?

    public init(
        cloudflare: CloudflareConfig? = nil,
        ssh: SshConfig? = nil
    ) {
        self.cloudflare = cloudflare
        self.ssh = ssh
    }

    /// Creates an Extensions configuration with cleaner static factory method.
    public static func extensions(
        cloudflare: CloudflareConfig? = nil,
        ssh: SshConfig? = nil
    ) -> Extensions {
        Extensions(cloudflare: cloudflare, ssh: ssh)
    }
}

// MARK: - Sites

/// Grouped site configuration.
///
/// Groups backend services and static pages that Arc will manage.
///
/// ## Example
///
/// ```swift
/// let sites = Sites(
///     services: [
///         .init(name: "api", domain: "api.local", port: 8000,
///               process: .init(workingDir: "apps/api/", executable: ".build/release/API"))
///     ],
///     pages: [
///         .init(name: "site", domain: "site.local", outputPath: "static/.output")
///     ]
/// )
/// ```
///
/// ## Topics
///
/// ### Site Types
///
/// - ``services``
/// - ``pages``
///
/// ## See Also
///
/// - ``ServiceSite``
/// - ``StaticSite``
public struct Sites: Codable, Sendable, Hashable {
    /// Backend or full-stack services.
    ///
    /// Array of dynamic applications that Arc will start, monitor, and proxy to.
    ///
    /// ## See Also
    ///
    /// - ``ServiceSite``
    public var services: [ServiceSite]

    /// Static pages (formerly `static`).
    ///
    /// Array of static site configurations that Arc will serve.
    ///
    /// ## See Also
    ///
    /// - ``StaticSite``
    public var pages: [StaticSite]

    public init(
        services: [ServiceSite] = [],
        pages: [StaticSite] = []
    ) {
        self.services = services
        self.pages = pages
    }

    /// Creates a Sites configuration with services and pages.
    public static func sites(
        services: [ServiceSite] = [],
        pages: [StaticSite] = []
    ) -> Sites {
        Sites(services: services, pages: pages)
    }

    /// Validates the sites configuration.
    internal func validate() throws {
        // Check for unique names across all sites
        let allNames = services.map(\.name) + pages.map(\.name)
        let duplicateNames = allNames.filter { name in allNames.filter { $0 == name }.count > 1 }
        if !duplicateNames.isEmpty {
            throw ValidationError.duplicateSiteNames(Array(Set(duplicateNames)))
        }

        // Check for unique ports
        let ports = services.map(\.port)
        let duplicatePorts = ports.filter { port in ports.filter { $0 == port }.count > 1 }
        if !duplicatePorts.isEmpty {
            throw ValidationError.duplicatePorts(Array(Set(duplicatePorts)))
        }
    }
}

// MARK: - ServiceSite

/// Service (app) site configuration.
///
/// Represents a backend service or full-stack application that Arc will manage.
/// Arc will start the process, monitor its health, and route traffic based on domain.
///
/// ## Example
///
/// ```swift
/// let service = ServiceSite(
///     name: "api",
///     domain: "api.example.com",
///     port: 8000,
///     healthPath: "/health",
///     process: .init(
///         workingDir: "apps/api/",
///         executable: ".build/release/APIServer",
///         env: ["DATABASE_URL": "postgresql://localhost/db"]
///     ),
///     watchTargets: ["apps/api/Sources/"]
/// )
/// ```
///
/// ## Topics
///
/// ### Required Properties
///
/// - ``name``
/// - ``domain``
/// - ``port``
/// - ``process``
///
/// ### Optional Properties
///
/// - ``healthPath``
/// - ``watchTargets``
///
/// ## See Also
///
/// - ``ProcessConfig``
/// - ``StaticSite``
public struct ServiceSite: Codable, Sendable, Hashable, Identifiable {
    /// Unique identifier for this site.
    ///
    /// Must be unique across all services and pages.
    ///
    /// - Precondition: Cannot be empty or contain whitespace
    public var name: String

    /// Domain to match for routing.
    ///
    /// Incoming requests with this domain will be routed to this service.
    ///
    /// - Precondition: Cannot be empty
    public var domain: String

    /// Port the application listens on.
    ///
    /// The local port where your application's HTTP server is listening.
    ///
    /// - Precondition: Must be in range 1025-65535 (unprivileged ports)
    public var port: Int

    /// Health check endpoint path.
    ///
    /// Arc will make GET requests to this path to verify the service is healthy.
    ///
    /// - Note: Default is `"/health"`
    /// - Precondition: Must start with `/`
    public var healthPath: String

    /// Process configuration.
    ///
    /// Defines how to start and manage the service process.
    ///
    /// ## See Also
    ///
    /// - ``ProcessConfig``
    public var process: ProcessConfig

    /// Watch targets override (optional).
    ///
    /// Specific file paths to watch for changes. When files in these paths change,
    /// Arc will restart the service. If `nil`, uses global watch configuration.
    public var watchTargets: [String]?

    /// Unique identifier conforming to `Identifiable`.
    public var id: String { name }

    /// Creates a ServiceSite with a cleaner static factory method.
    public static func service(
        name: String,
        domain: String,
        port: Int,
        healthPath: String = "/health",
        process: ProcessConfig,
        watchTargets: [String]? = nil
    ) -> ServiceSite {
        ServiceSite(
            name: name,
            domain: domain,
            port: port,
            healthPath: healthPath,
            process: process,
            watchTargets: watchTargets
        )
    }

    public init(
        name: String,
        domain: String,
        port: Int,
        healthPath: String = "/health",
        process: ProcessConfig,
        watchTargets: [String]? = nil
    ) {
        // Validate name
        precondition(!name.isEmpty, "Service name cannot be empty")
        precondition(!name.contains(where: \.isWhitespace), "Service name cannot contain whitespace, got '\(name)'")

        // Validate domain
        precondition(!domain.isEmpty, "Service domain cannot be empty")

        // Validate port
        precondition(port > 1024 && port < 65536, "Service port must be in range 1025-65535 (unprivileged), got \(port)")

        // Validate health path
        precondition(healthPath.hasPrefix("/"), "Health check path must start with '/', got '\(healthPath)'")

        self.name = name
        self.domain = domain
        self.port = port
        self.healthPath = healthPath
        self.process = process
        self.watchTargets = watchTargets
    }
}

// MARK: - StaticSite

/// Static site configuration.
///
/// Represents a static site (HTML, CSS, JavaScript) that Arc will serve.
/// Arc routes traffic to the static files based on domain.
///
/// ## Example
///
/// ```swift
/// let site = StaticSite(
///     name: "portfolio",
///     domain: "example.com",
///     outputPath: "static/portfolio/.output",
///     watchTargets: ["static/portfolio/Sources/"]
/// )
/// ```
///
/// ## Topics
///
/// ### Required Properties
///
/// - ``name``
/// - ``domain``
/// - ``outputPath``
///
/// ### Optional Properties
///
/// - ``watchTargets``
///
/// ## See Also
///
/// - ``ServiceSite``
public struct StaticSite: Codable, Sendable, Hashable, Identifiable {
    /// Unique identifier for this site.
    ///
    /// Must be unique across all services and pages.
    ///
    /// - Precondition: Cannot be empty or contain whitespace
    public var name: String

    /// Domain to match for routing.
    ///
    /// Incoming requests with this domain will be routed to serve files from `outputPath`.
    ///
    /// - Precondition: Cannot be empty
    public var domain: String

    /// Path to the output directory relative to `baseDir`.
    ///
    /// The directory containing the built static files (HTML, CSS, JS, etc.).
    ///
    /// - Precondition: Cannot be empty
    public var outputPath: String

    /// Watch targets override (optional).
    ///
    /// Specific file paths to watch for changes. When files in these paths change,
    /// Arc can trigger a rebuild. If `nil`, uses global watch configuration.
    public var watchTargets: [String]?

    /// Unique identifier conforming to `Identifiable`.
    public var id: String { name }

    /// Creates a StaticSite with a cleaner static factory method.
    public static func page(
        name: String,
        domain: String,
        outputPath: String,
        watchTargets: [String]? = nil
    ) -> StaticSite {
        StaticSite(
            name: name,
            domain: domain,
            outputPath: outputPath,
            watchTargets: watchTargets
        )
    }

    public init(
        name: String,
        domain: String,
        outputPath: String,
        watchTargets: [String]? = nil
    ) {
        // Validate name
        precondition(!name.isEmpty, "Static site name cannot be empty")
        precondition(!name.contains(where: \.isWhitespace), "Static site name cannot contain whitespace, got '\(name)'")

        // Validate domain
        precondition(!domain.isEmpty, "Static site domain cannot be empty")

        // Validate output path
        precondition(!outputPath.isEmpty, "Output path cannot be empty")

        self.name = name
        self.domain = domain
        self.outputPath = outputPath
        self.watchTargets = watchTargets
    }
}

// MARK: - ProcessConfig

/// Process configuration for app sites.
///
/// Defines how Arc should start and manage a service process.
/// You can specify either an executable path or a command to run.
///
/// ## Examples
///
/// Using an executable:
/// ```swift
/// let process = ProcessConfig(
///     workingDir: "apps/api/",
///     executable: ".build/release/APIServer",
///     env: ["PORT": "8000", "LOG_LEVEL": "debug"]
/// )
/// ```
///
/// Using a command:
/// ```swift
/// let process = ProcessConfig(
///     workingDir: "apps/api/",
///     command: "swift",
///     args: ["run", "APIServer"],
///     env: ["PORT": "8000"]
/// )
/// ```
///
/// ## Topics
///
/// ### Required Properties
///
/// - ``workingDir``
///
/// ### Execution Method (pick one)
///
/// - ``executable``
/// - ``command``
///
/// ### Optional Properties
///
/// - ``args``
/// - ``env``
public struct ProcessConfig: Codable, Sendable, Hashable {
    /// Working directory relative to `baseDir`.
    ///
    /// The process will be started in this directory.
    ///
    /// - Precondition: Cannot be empty
    public var workingDir: String

    /// Path to executable (relative to workingDir or absolute).
    ///
    /// Direct path to a binary to execute. Use this for compiled executables.
    ///
    /// - Note: Either `executable` or `command` must be provided, but not both
    /// - Precondition: Cannot be empty if provided
    public var executable: String?

    /// Command to run (alternative to executable).
    ///
    /// Name of a command to run (e.g., "swift", "node", "python").
    /// The command must be in PATH or use an absolute path.
    ///
    /// - Note: Either `executable` or `command` must be provided, but not both
    /// - Precondition: Cannot be empty if provided
    public var command: String?

    /// Arguments for command.
    ///
    /// Command-line arguments passed to the command or executable.
    public var args: [String]?

    /// Environment variables.
    ///
    /// Environment variables to set for the process. These are merged with
    /// the parent process's environment.
    public var env: [String: String]?

    /// Creates a ProcessConfig with a cleaner static factory method.
    public static func process(
        workingDir: String,
        executable: String? = nil,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil
    ) -> ProcessConfig {
        ProcessConfig(
            workingDir: workingDir,
            executable: executable,
            command: command,
            args: args,
            env: env
        )
    }

    public init(
        workingDir: String,
        executable: String? = nil,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil
    ) {
        // Validate working directory
        precondition(!workingDir.isEmpty, "Working directory cannot be empty")

        // Validate that either executable or command is provided
        precondition(
            executable != nil || command != nil,
            "Either executable or command must be provided"
        )

        // Validate that executable and command are not empty if provided
        if let exec = executable {
            precondition(!exec.isEmpty, "Executable path cannot be empty")
        }
        if let cmd = command {
            precondition(!cmd.isEmpty, "Command cannot be empty")
        }

        self.workingDir = workingDir
        self.executable = executable
        self.command = command
        self.args = args
        self.env = env
    }
}

// MARK: - WatchConfig

/// Global watch configuration.
///
/// Controls file watching and hot-reload behavior for Arc.
///
/// ## Example
///
/// ```swift
/// let watch = WatchConfig(
///     enabled: true,
///     watchConfig: true,
///     followSymlinks: false,
///     debounceMs: 300,
///     cooldownMs: 1000
/// )
/// ```
///
/// ## Topics
///
/// ### Watch Behavior
///
/// - ``enabled``
/// - ``watchConfig``
/// - ``followSymlinks``
///
/// ### Timing
///
/// - ``debounceMs``
/// - ``cooldownMs``
public struct WatchConfig: Codable, Sendable, Hashable {
    /// Whether file watching is enabled.
    ///
    /// When `true`, Arc monitors files for changes and automatically reloads.
    ///
    /// - Note: Default is `true`
    public var enabled: Bool

    /// Whether to watch the manifest for changes.
    ///
    /// When `true`, Arc watches `Arc.swift` and reloads configuration
    /// when it changes.
    ///
    /// - Note: Default is `true`
    public var watchConfig: Bool

    /// Whether to follow symlinks when watching.
    ///
    /// When `true`, Arc follows symbolic links when watching directories.
    /// For security, this is disabled by default.
    ///
    /// - Note: Default is `false`
    public var followSymlinks: Bool

    /// Debounce interval in milliseconds.
    ///
    /// After a file change is detected, Arc waits this long for additional
    /// changes before triggering a reload. This prevents rapid repeated reloads.
    ///
    /// - Note: Default is `300` milliseconds
    /// - Precondition: Must be non-negative
    public var debounceMs: Int

    /// Cooldown period in milliseconds after restart.
    ///
    /// After restarting a service, Arc ignores file changes for this duration
    /// to prevent restart loops.
    ///
    /// - Note: Default is `1000` milliseconds (1 second)
    /// - Precondition: Must be non-negative
    public var cooldownMs: Int

    /// Creates a WatchConfig with a cleaner static factory method.
    public static func watch(
        enabled: Bool = true,
        watchConfig: Bool = true,
        followSymlinks: Bool = false,
        debounceMs: Int = 300,
        cooldownMs: Int = 1000
    ) -> WatchConfig {
        WatchConfig(
            enabled: enabled,
            watchConfig: watchConfig,
            followSymlinks: followSymlinks,
            debounceMs: debounceMs,
            cooldownMs: cooldownMs
        )
    }

    public init(
        enabled: Bool = true,
        watchConfig: Bool = true,
        followSymlinks: Bool = false,
        debounceMs: Int = 300,
        cooldownMs: Int = 1000
    ) {
        // Validate debounce interval
        precondition(debounceMs >= 0, "Debounce interval must be non-negative, got \(debounceMs)")

        // Validate cooldown period
        precondition(cooldownMs >= 0, "Cooldown period must be non-negative, got \(cooldownMs)")

        self.enabled = enabled
        self.watchConfig = watchConfig
        self.followSymlinks = followSymlinks
        self.debounceMs = debounceMs
        self.cooldownMs = cooldownMs
    }
}

// MARK: - CloudflareConfig

/// Cloudflare Tunnel configuration.
///
/// Configures Cloudflare Tunnel integration for exposing local services to the internet.
///
/// ## Example
///
/// ```swift
/// let cloudflare = CloudflareConfig(
///     enabled: true,
///     cloudflaredPath: "/opt/homebrew/bin/cloudflared",
///     tunnelName: "my-tunnel",
///     tunnelUUID: "12345678-1234-1234-1234-123456789abc"
/// )
/// ```
///
/// ## Topics
///
/// ### Configuration
///
/// - ``enabled``
/// - ``cloudflaredPath``
/// - ``tunnelName``
/// - ``tunnelUUID``
///
/// ## See Also
///
/// - ``SshConfig``
public struct CloudflareConfig: Codable, Sendable, Hashable {
    /// Whether to enable the Cloudflare Tunnel.
    ///
    /// When `true`, Arc starts cloudflared and routes traffic through the tunnel.
    ///
    /// - Note: Default is `false`
    /// - Precondition: When enabled, either `tunnelName` or `tunnelUUID` must be provided
    public var enabled: Bool

    /// Path to cloudflared executable.
    ///
    /// Path to the `cloudflared` binary. Can be absolute or relative.
    ///
    /// - Note: Default is `"/opt/homebrew/bin/cloudflared"`
    /// - Precondition: Cannot be empty
    public var cloudflaredPath: String

    /// Tunnel name or ID.
    ///
    /// Human-readable tunnel name from your Cloudflare dashboard.
    public var tunnelName: String?

    /// Tunnel UUID (optional).
    ///
    /// UUID identifier for the tunnel from your Cloudflare dashboard.
    public var tunnelUUID: String?

    /// Creates a CloudflareConfig with a cleaner static factory method.
    public static func cloudflare(
        enabled: Bool = false,
        cloudflaredPath: String = "/opt/homebrew/bin/cloudflared",
        tunnelName: String? = nil,
        tunnelUUID: String? = nil
    ) -> CloudflareConfig {
        CloudflareConfig(
            enabled: enabled,
            cloudflaredPath: cloudflaredPath,
            tunnelName: tunnelName,
            tunnelUUID: tunnelUUID
        )
    }

    public init(
        enabled: Bool = false,
        cloudflaredPath: String = "/opt/homebrew/bin/cloudflared",
        tunnelName: String? = nil,
        tunnelUUID: String? = nil
    ) {
        // Validate cloudflared path
        precondition(!cloudflaredPath.isEmpty, "Cloudflared path cannot be empty")

        // If enabled, require tunnel name or UUID
        if enabled {
            precondition(
                tunnelName != nil || tunnelUUID != nil,
                "When Cloudflare tunnel is enabled, either tunnelName or tunnelUUID must be provided"
            )
        }

        self.enabled = enabled
        self.cloudflaredPath = cloudflaredPath
        self.tunnelName = tunnelName
        self.tunnelUUID = tunnelUUID
    }
}

// MARK: - SshConfig

/// SSH configuration for Cloudflare tunnel access.
///
/// Enables SSH access to your server through a Cloudflare tunnel.
///
/// ## Example
///
/// ```swift
/// let ssh = SshConfig(
///     enabled: true,
///     domain: "ssh.example.com",
///     port: 22
/// )
/// ```
///
/// ## Topics
///
/// ### Configuration
///
/// - ``enabled``
/// - ``domain``
/// - ``port``
///
/// ## See Also
///
/// - ``CloudflareConfig``
public struct SshConfig: Codable, Sendable, Hashable {
    /// Whether to enable SSH access via Cloudflare tunnel.
    ///
    /// When `true`, Arc configures the Cloudflare tunnel to forward SSH traffic.
    ///
    /// - Note: Default is `false`
    /// - Precondition: When enabled, `domain` must be provided
    public var enabled: Bool

    /// Domain for SSH access via Cloudflare tunnel.
    ///
    /// The domain that will route to SSH (e.g., "ssh.example.com").
    ///
    /// - Precondition: Required when `enabled` is `true`, cannot be empty
    public var domain: String?

    /// Local SSH port to forward.
    ///
    /// The local SSH server port to forward through the tunnel.
    ///
    /// - Note: Default is `22`
    /// - Precondition: Must be in range 1-65535
    public var port: Int

    /// Creates an SshConfig with a cleaner static factory method.
    public static func ssh(
        enabled: Bool = false,
        domain: String? = nil,
        port: Int = 22
    ) -> SshConfig {
        SshConfig(
            enabled: enabled,
            domain: domain,
            port: port
        )
    }

    public init(
        enabled: Bool = false,
        domain: String? = nil,
        port: Int = 22
    ) {
        // Validate SSH port
        precondition(port > 0 && port < 65536, "SSH port must be in range 1-65535, got \(port)")

        // If enabled, require domain
        if enabled {
            precondition(domain != nil && !domain!.isEmpty, "When SSH is enabled, domain must be provided")
        }

        self.enabled = enabled
        self.domain = domain
        self.port = port
    }
}

// MARK: - ValidationError

/// Errors that can occur during configuration validation.
///
/// Thrown when configuration constraints are violated.
///
/// ## Topics
///
/// ### Error Cases
///
/// - ``duplicateSiteNames(_:)``
/// - ``duplicatePorts(_:)``
public enum ValidationError: Error, CustomStringConvertible {
    /// Duplicate site names were found in the configuration.
    ///
    /// Site names must be unique across all services and pages.
    ///
    /// - Parameter names: Array of duplicate names found
    case duplicateSiteNames([String])

    /// Duplicate ports were found in service configurations.
    ///
    /// Each service must use a unique port.
    ///
    /// - Parameter ports: Array of duplicate ports found
    case duplicatePorts([Int])

    /// Human-readable error description.
    public var description: String {
        switch self {
        case .duplicateSiteNames(let names):
            return "Duplicate site names found: \(names.joined(separator: ", "))"
        case .duplicatePorts(let ports):
            return "Duplicate ports found: \(ports.map(String.init).joined(separator: ", "))"
        }
    }
}
