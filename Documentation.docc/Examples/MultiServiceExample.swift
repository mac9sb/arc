// Multi-Service ArcManifest.swift Example
// This demonstrates a typical setup with multiple services and static sites.

import ArcDescription

let config = ArcConfiguration(
    processName: "web-platform",
    sites: .init(
        services: [
            // API Service
            .init(
                name: "api",
                domain: "api.example.com",
                port: 8000,
                healthPath: "/health",
                process: .init(
                    workingDir: "apps/api/Web/",
                    executable: ".build/release/APIServer"
                )
            ),

            // Guest List App
            .init(
                name: "guest-list",
                domain: "guests.example.com",
                port: 8001,
                process: .init(
                    workingDir: "apps/guest-list/Web/",
                    executable: ".build/release/GuestListWeb",
                    env: [
                        "DATABASE_URL": "sqlite:///data/guestlist.db"
                    ]
                )
            ),

            // Admin Dashboard
            .init(
                name: "admin",
                domain: "admin.example.com",
                port: 8002,
                process: .init(
                    workingDir: "apps/admin/Web/",
                    executable: ".build/release/AdminWeb"
                ),
                watchTargets: ["apps/admin/"]
            )
        ],
        pages: [
            // Main Marketing Site
            .init(
                name: "marketing",
                domain: "example.com",
                outputPath: "static/marketing/.output"
            ),

            // Documentation Site
            .init(
                name: "docs",
                domain: "docs.example.com",
                outputPath: "static/docs/.output",
                watchTargets: ["static/docs/"]
            )
        ]
    ),
    cloudflare: .init(
        enabled: true,
        tunnelName: "example-tunnel",
        tunnelUUID: "12345678-1234-1234-1234-123456789abc"
    )
)
