import Foundation
import Noora

/// Error types for cloudflared configuration and startup.
public enum CloudflaredConfigError: Error, Equatable {
    case tunnelIdentifierRequired
    case processExitedImmediately(pid: pid_t, logPath: String)
    case credentialsFileMissing(tunnelUUID: String, credentialsPath: String)

    /// Returns an ErrorAlert for display with Noora.
    public var errorAlert: ErrorAlert {
        switch self {
        case .tunnelIdentifierRequired:
            return .alert(
                "Cloudflare tunnel is enabled but no tunnel identifier is configured",
                takeaways: [
                    "Set a tunnel name or UUID in config.pkl:",
                    "cloudflare {",
                    "  enabled = true",
                    "  tunnelName = \"maclong-tunnel\"",
                    "  // or tunnelUUID = \"<uuid>\"",
                    "}",
                    "Login to Cloudflare if needed: \(.command("cloudflared tunnel login"))",
                    "Create a new tunnel: \(.command("cloudflared tunnel create <tunnel-name>"))",
                ]
            )
        case .processExitedImmediately(let pid, let logPath):
            return .alert(
                "Cloudflared tunnel failed to start",
                takeaways: [
                    "The cloudflared process (PID: \(pid)) exited immediately after starting",
                    "This usually indicates an authentication or tunnel error",
                    "Check the log file: \(logPath)",
                    "",
                    "Common issues and solutions:",
                    "1. Not logged in to Cloudflare:",
                    "   Run: \(.command("cloudflared tunnel login"))",
                    "",
                    "2. Tunnel not created:",
                    "   Create a tunnel: \(.command("cloudflared tunnel create <TUNNEL_NAME>"))",
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

public enum CloudflaredCredentials {
    /// Generates the credentials file path from tunnel UUID.
    public static func filePath(tunnelUUID: String) -> String {
        let homeDir = NSHomeDirectory()
        return "\(homeDir)/.cloudflared/\(tunnelUUID).json"
    }
}
