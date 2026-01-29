// Full-Featured ArcManifest.swift Example
// This demonstrates all available configuration options in ArcDescription.

import Foundation
import ArcDescription

// Example: Use environment variables for dynamic configuration
let isDevelopment = ProcessInfo.processInfo.environment["ENV"] == "development"
let dbHost = ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost"

let config = ArcConfiguration(
    // Proxy server configuration
    proxyPort: isDevelopment ? 8080 : 80,

    // Log directory (expands tilde automatically)
    logDir: isDevelopment ? "~/Library/Logs/arc" : "/var/log/arc",

    // Base directory for all projects (optional - defaults to manifest directory)
    baseDir: nil,

    // Health check interval in seconds
    healthCheckInterval: 30,

    // Server version displayed in status
    version: "V.2.0.0",

    // Deployment region identifier
    region: "us-west-2",

    // Process name for this arc instance
    processName: "production-cluster",

    // Site configuration
    sites: .init(
        // Backend/full-stack services
        services: [
            // Example: Full-featured service with all options
            .init(
                name: "api-gateway",
                domain: "api.example.com",
                port: 8000,
                healthPath: "/health",
                process: .init(
                    workingDir: "apps/api-gateway/Web/",
                    executable: ".build/arm64-apple-macosx/release/APIGateway",
                    env: [
                        "DATABASE_URL": "postgresql://\(dbHost):5432/api",
                        "REDIS_URL": "redis://\(dbHost):6379",
                        "LOG_LEVEL": isDevelopment ? "debug" : "info",
                        "API_KEY": ProcessInfo.processInfo.environment["API_KEY"] ?? ""
                    ]
                ),
                watchTargets: [
                    "apps/api-gateway/Sources/",
                    "apps/api-gateway/Package.swift"
                ]
            ),

            // Example: Service using command instead of executable
            .init(
                name: "worker",
                domain: "worker.example.com",
                port: 8001,
                healthPath: "/status",
                process: .init(
                    workingDir: "apps/worker/",
                    command: "swift",
                    args: ["run", "WorkerService"],
                    env: [
                        "QUEUE_URL": "redis://\(dbHost):6379/1",
                        "WORKER_THREADS": "4"
                    ]
                )
            ),

            // Example: Minimal service configuration
            .init(
                name: "auth-service",
                domain: "auth.example.com",
                port: 8002,
                process: .init(
                    workingDir: "apps/auth/Web/",
                    executable: ".build/release/AuthService"
                )
            )
        ],

        // Static page sites
        pages: [
            // Example: Main marketing site
            .init(
                name: "marketing",
                domain: "example.com",
                outputPath: "static/marketing/.output",
                watchTargets: [
                    "static/marketing/Sources/",
                    "static/marketing/Package.swift"
                ]
            ),

            // Example: Documentation site
            .init(
                name: "docs",
                domain: "docs.example.com",
                outputPath: "static/docs/.output"
            ),

            // Example: Blog
            .init(
                name: "blog",
                domain: "blog.example.com",
                outputPath: "static/blog/.output"
            )
        ]
    ),

    // Cloudflare Tunnel configuration
    cloudflare: .init(
        enabled: true,
        cloudflaredPath: "/opt/homebrew/bin/cloudflared",
        tunnelName: "my-production-tunnel",
        tunnelUUID: "12345678-1234-1234-1234-123456789abc"
    ),

    // SSH access via Cloudflare tunnel
    ssh: .init(
        enabled: true,
        domain: "ssh.example.com",
        port: 22
    ),

    // File watching and hot-reload configuration
    watch: .init(
        enabled: true,
        watchConfig: true,           // Watch this manifest for changes
        followSymlinks: false,        // Don't follow symlinks (security)
        debounceMs: 300,              // Wait 300ms after last change
        cooldownMs: 1000              // Wait 1s after restart before accepting new changes
    )
)
