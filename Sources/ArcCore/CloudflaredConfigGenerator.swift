import Foundation
import Noora

/// Error types for cloudflared configuration generation.
public enum CloudflaredConfigError: Error {
    case tunnelUUIDRequired
    case noSitesConfigured
    case configWriteFailed(String)

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
                    "Copy the tunnel UUID and add it to your config.pkl or set \(.accent("CLOUDFLARE_TUNNEL_UUID")) environment variable"
                ]
            )
        case .noSitesConfigured:
            return .alert(
                "No sites with domains configured",
                takeaways: [
                    "Cannot generate cloudflared ingress rules without site domains",
                    "Add at least one site with a domain to your config.pkl"
                ]
            )
        case .configWriteFailed(let message):
            return .alert(
                "Failed to write cloudflared config file",
                takeaways: [
                    "Error: \(message)",
                    "Ensure the config directory exists and is writable"
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

        // Extract domains from sites
        let domains = extractDomains(from: config.sites)
        guard !domains.isEmpty else {
            throw CloudflaredConfigError.noSitesConfigured
        }

        // Generate credentials file path
        let credentialsPath = generateCredentialsFilePath(tunnelUUID: tunnelUUID)

        // Build YAML
        var yaml = "tunnel: \(tunnelUUID)\n"
        yaml += "credentials-file: \(credentialsPath)\n"
        yaml += "ingress:\n"

        // Add ingress rules for each domain
        for domain in domains {
            yaml += "  - hostname: \(domain)\n"
            yaml += "    service: http://localhost:\(config.proxyPort)\n"
            yaml += "    originRequest:\n"
            yaml += "      httpHostHeader: \(domain)\n"
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
    private static func generateCredentialsFilePath(tunnelUUID: String) -> String {
        let homeDir = NSHomeDirectory()
        return "\(homeDir)/.cloudflared/\(tunnelUUID).json"
    }

    /// Extracts unique domains from sites.
    ///
    /// - Parameter sites: Array of sites.
    /// - Returns: Array of unique domain strings.
    private static func extractDomains(from sites: [Site]) -> [String] {
        var domains: Set<String> = []
        for site in sites {
            switch site {
            case .static(let staticSite):
                domains.insert(staticSite.domain)
            case .app(let appSite):
                domains.insert(appSite.domain)
            }
        }
        return Array(domains).sorted()
    }

    /// Expands a path, handling `~` and relative paths.
    ///
    /// - Parameter path: The path to expand.
    /// - Returns: The expanded absolute path.
    private static func expandPath(_ path: String) -> String {
        return (path as NSString).expandingTildeInPath
    }
}
