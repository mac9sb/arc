// Multi-Service ArcManifest.swift Example
// This demonstrates a typical setup with multiple services and static sites.

import ArcDescription

let config = ArcConfiguration(
    processName: "web-platform",
    sites: [
        // API Service
        .service(
            name: "api",
            domain: "api.example.com",
            port: 8000,
            healthPath: "/health",
            process: .process(
                workingDir: "apps/api/Web/",
                executable: ".build/release/APIServer"
            )
        ),

        // Guest List App
        .service(
            name: "guest-list",
            domain: "guests.example.com",
            port: 8001,
            process: .process(
                workingDir: "apps/guest-list/Web/",
                executable: ".build/release/GuestListWeb",
                env: [
                    "DATABASE_URL": "sqlite:///data/guestlist.db"
                ]
            )
        ),

        // Admin Dashboard
        .service(
            name: "admin",
            domain: "admin.example.com",
            port: 8002,
            process: .process(
                workingDir: "apps/admin/Web/",
                executable: ".build/release/AdminWeb"
            ),
            watchTargets: ["apps/admin/"]
        ),

        // Main Marketing Site
        .page(
            name: "marketing",
            domain: "example.com",
            outputPath: "static/marketing/.output"
        ),

        // Documentation Site
        .page(
            name: "docs",
            domain: "docs.example.com",
            outputPath: "static/docs/.output",
            watchTargets: ["static/docs/"]
        ),
    ],
    extensions: [
        .cloudflare(
            tunnelName: "example-tunnel",
            tunnelUUID: "12345678-1234-1234-1234-123456789abc"
        )
    ]
)
