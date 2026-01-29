// Basic ArcManifest.swift Example
// This demonstrates the minimal configuration needed for a single static site.

import ArcDescription

let config = ArcConfiguration(
    processName: "my-server",
    sites: .init(
        services: [],
        pages: [
            .init(
                name: "portfolio",
                domain: "example.com",
                outputPath: "static/portfolio/.output"
            )
        ]
    )
)
