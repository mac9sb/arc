import Foundation
import Noora

/// Error types for cloudflared configuration generation.
public enum CloudflaredConfigError: Error, Equatable {
    case tunnelUUIDRequired
    case noSitesConfigured
    case sshDomainRequired
    case configWriteFailed(String)
    case processExitedImmediately(pid: pid_t, logPath: String)
    case credentialsFileMissing(tunnelUUID: String, credentialsPath: String)

    /// Returns an ErrorAlert for display with Noora.
    public var errorAlert: ErrorAlert {
        switch self {
        case .tunnelUUIDRequired:
            return .alert(
                "Cloudflare tunnel is enabled but tunnelUUID is missing in config.pkl",
                takeaways: [
                    "Install cloudflared: \(.command("brew install cloudflared"))",
                    "Or download from: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/",
                    "Login to Cloudflare: \(.command("cloudflared tunnel login"))",
                    "Create a new tunnel: \(.command("cloudflared tunnel create <tunnel-name>"))",
                    "Copy the tunnel UUID and add it to your config.pkl or set \(.accent("CLOUDFLARE_TUNNEL_UUID")) environment variable",
                ]
            )
        case .noSitesConfigured:
            return .alert(
                "No sites with domains configured",
                takeaways: [
                    "Cannot generate cloudflared ingress rules without site domains",
                    "Add at least one site with a domain to your config.pkl",
                ]
            )
        case .sshDomainRequired:
            return .alert(
                "SSH is enabled but domain is missing in config.pkl",
                takeaways: [
                    "Add a domain to your ssh configuration:",
                    "ssh {",
                    "  enabled = true",
                    "  domain = \"ssh.maclong.dev\"",
                    "}",
                ]
            )
        case .configWriteFailed(let message):
            return .alert(
                "Failed to write cloudflared config file",
                takeaways: [
                    "Error: \(message)",
                    "Ensure the config directory exists and is writable",
                ]
            )
        case .processExitedImmediately(let pid, let logPath):
            return .alert(
                "Cloudflared tunnel failed to start",
                takeaways: [
                    "The cloudflared process (PID: \(pid)) exited immediately after starting",
                    "This usually indicates a configuration or authentication error",
                    "Check the log file: \(logPath)",
                    "",
                    "Common issues and solutions:",
                    "1. Not logged in to Cloudflare:",
                    "   Run: \(.command("cloudflared tunnel login"))",
                    "",
                    "2. Tunnel not created:",
                    "   Create a tunnel: \(.command("cloudflared tunnel create <TUNNEL_NAME>"))",
                    "   This will output a tunnel UUID - add it to config.pkl",
                    "",
                    "3. Missing credentials file:",
                    "   The file ~/.cloudflared/<TUNNEL_UUID>.json must exist",
                    "   Option A - Create new tunnel (recommended):",
                    "     Run: \(.command("cloudflared tunnel create <TUNNEL_NAME>"))",
                    "     This automatically creates ~/.cloudflared/<TUNNEL_UUID>.json",
                    "   Option B - For existing tunnels, get credentials:",
                    "     Run: \(.command("cloudflared tunnel token --cred-file ~/.cloudflared/<TUNNEL_UUID>.json <TUNNEL_NAME>"))",
                    "     Or using UUID: \(.command("cloudflared tunnel token --cred-file ~/.cloudflared/<TUNNEL_UUID>.json <TUNNEL_UUID>"))",
                    "     Note: Use --cred-file (with hyphen), not --credfile",
                    "     Note: This command only works for tunnels created since cloudflared version 2022.3.0",
                    "",
                    "4. Invalid tunnel UUID:",
                    "   Verify the tunnel UUID in config.pkl matches your Cloudflare tunnel",
                    "   List tunnels: \(.command("cloudflared tunnel list"))",
                    "",
                    "5. Check cloudflared logs for details:",
                    "   \(.command("cat \(logPath)"))",
                ]
            )
        case .credentialsFileMissing(let tunnelUUID, let credentialsPath):
            return .alert(
                "Cloudflared credentials file not found",
                takeaways: [
                    "The credentials file is missing: \(credentialsPath)",
                    "This file is required to authenticate with Cloudflare",
                    "",
                    "To get the credentials file:",
                    "Option A - Create new tunnel (recommended):",
                    "  Run: \(.command("cloudflared tunnel create <TUNNEL_NAME>"))",
                    "  This automatically creates ~/.cloudflared/<TUNNEL_UUID>.json",
                    "",
                    "Option B - For existing tunnels, get credentials:",
                    "  Run: \(.command("cloudflared tunnel token --cred-file ~/.cloudflared/<TUNNEL_UUID>.json <TUNNEL_NAME>"))",
                    "  Or using UUID: \(.command("cloudflared tunnel token --cred-file ~/.cloudflared/<TUNNEL_UUID>.json <TUNNEL_UUID>"))",
                    "  Note: Use --cred-file (with hyphen), not --credfile",
                    "  Note: This command only works for tunnels created since cloudflared version 2022.3.0",
                    "",
                    "Expected file location: \(credentialsPath)",
                    "Tunnel UUID: \(tunnelUUID)",
                ]
            )
        }
    }
}

/// Generates cloudflared YAML configuration from Arc configuration.
public struct CloudflaredConfigGenerator {
    /// Generates the cloudflared config YAML string from Arc configuration.
    ///
    /// - Parameters:
    ///   - config: The Arc configuration.
    ///   - tunnel: The Cloudflare tunnel configuration.
    /// - Returns: YAML string for cloudflared config.
    /// - Throws: `CloudflaredConfigError` if validation fails.
    public static func generateConfig(config: ArcConfig, tunnel: CloudflareTunnel) throws -> String {
        // Validate tunnel UUID is present
        guard let tunnelUUID = tunnel.tunnelUUID, !tunnelUUID.isEmpty else {
            throw CloudflaredConfigError.tunnelUUIDRequired
        }

        // Build domain → port mapping: app sites use their port, static sites use proxy port
        let domainPorts = extractDomainPorts(from: config.sites, proxyPort: config.proxyPort)
        guard !domainPorts.isEmpty else {
            throw CloudflaredConfigError.noSitesConfigured
        }

        // Generate credentials file path
        let credentialsPath = generateCredentialsFilePath(tunnelUUID: tunnelUUID)

        // Build YAML
        var yaml = "tunnel: \(tunnelUUID)\n"
        yaml += "credentials-file: \(credentialsPath)\n"
        yaml += "ingress:\n"

        // Add ingress rules for each domain (use site-specific port)
        for (domain, port) in domainPorts.sorted(by: { $0.0 < $1.0 }) {
            yaml += "  - hostname: \(domain)\n"
            yaml += "    service: http://localhost:\(port)\n"
            yaml += "    originRequest:\n"
            yaml += "      httpHostHeader: \(domain)\n"
        }

        // Add SSH ingress rule if enabled
        if let ssh = config.ssh, ssh.enabled {
            guard let sshDomain = ssh.domain, !sshDomain.isEmpty else {
                throw CloudflaredConfigError.sshDomainRequired
            }
            yaml += "  - hostname: \(sshDomain)\n"
            yaml += "    service: ssh://localhost:\(ssh.port)\n"
        }

        // Add catch-all rule
        yaml += "  - service: http_status:404\n"

        return yaml
    }

    /// Writes the cloudflared config to the specified path.
    ///
    /// - Parameters:
    ///   - config: The Arc configuration.
    ///   - tunnel: The Cloudflare tunnel configuration.
    /// - Throws: `CloudflaredConfigError` if generation or writing fails.
    public static func writeConfig(config: ArcConfig, tunnel: CloudflareTunnel) throws {
        let yaml = try generateConfig(config: config, tunnel: tunnel)
        let configPath = expandPath(tunnel.configPath)

        // Create parent directory if needed
        let fileManager = FileManager.default
        let configDir = (configPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: configDir) {
            try fileManager.createDirectory(
                atPath: configDir,
                withIntermediateDirectories: true
            )
        }

        // Write config file
        do {
            try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            throw CloudflaredConfigError.configWriteFailed(error.localizedDescription)
        }
    }

    /// Generates the credentials file path from tunnel UUID.
    ///
    /// - Parameter tunnelUUID: The tunnel UUID.
    /// - Returns: The expanded credentials file path.
    public static func generateCredentialsFilePath(tunnelUUID: String) -> String {
        let homeDir = NSHomeDirectory()
        return "\(homeDir)/.cloudflared/\(tunnelUUID).json"
    }

    /// Extracts domain → port mapping from sites.
    /// App sites use their configured port (e.g. 8000); static sites use the proxy port.
    ///
    /// - Parameters:
    ///   - sites: Array of sites.
    ///   - proxyPort: Port the Arc proxy listens on (used for static sites).
    /// - Returns: Array of (domain, port) tuples.
    private static func extractDomainPorts(from sites: [Site], proxyPort: Int) -> [(String, Int)] {
        var result: [(String, Int)] = []
        for site in sites {
            switch site {
            case .static(let staticSite):
                result.append((staticSite.domain, proxyPort))
            case .app(let appSite):
                result.append((appSite.domain, appSite.port))
            }
        }
        return result
    }

    /// Expands a path, handling `~` and relative paths.
    ///
    /// - Parameter path: The path to expand.
    /// - Returns: The expanded absolute path.
    private static func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
