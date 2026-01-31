# Server Workflow

This guide explains how the Developer Server monorepo works, how to run it locally, and how to add new static sites, services, apps, and embedded projects. It also covers best practices and links to external guides.

## Overview

The monorepo is organized around four primary workflows:

- **Static sites** (`sites/<site-name>/`) — generated content written in Swift using WebUI.
- **Services (server apps)** (`sites/<app-name>/Web/`) — Hummingbird-based web services.
- **Apps** (`apps/<app-name>/`) — product or design artifacts (often pre-development).
- **Embedded** (`embedded/<project-name>/`) — Embedded Swift projects targeting hardware.

The local server is orchestrated by **Arc**, which reads `Arc.swift` and manages processes, routing, and file watching.

## Local Server Workflow

### 1) Build tools (once)

Arc and WebUI live in `tooling/`. Build them before you run the server:

    cd tooling/arc && swift build -c release
    cd ../web-ui && swift build -c release

### 2) Run Arc

From the repo root:

    arc run

If `arc` is not on your PATH, run the binary directly or add it to PATH. Use the path that matches your machine’s architecture:

    ./tooling/arc/.build/arm64-apple-macosx/release/arc
    ./tooling/arc/.build/x86_64-apple-macosx/release/arc

Useful commands:

- `arc run` — start in foreground
- `arc run --background` — start in background
- `arc status` — show running services
- `arc logs` — stream logs
- `arc stop` — stop all processes

### 3) Verify routing

Arc uses `Arc.swift` to route based on domain. Each site or service should be listed there with its domain and process/output configuration.

## Adding a New Static Site

Static sites generate output into `.output` and are served by Arc as a `.page`.

### 1) Create the site

Create a new package under `sites/` with an executable target that generates HTML into `.output`. If you're using WebUI, your executable should write to the output path.

Example structure:

    sites/my-site/
    ├── Package.swift
    ├── Sources/
    │   └── MySite/
    └── .output/

### 2) Add to `Arc.swift`

    .page(
        name: "my-site",
        domain: "my-site.localhost",
        outputPath: "sites/my-site/.output"
    )

### 3) Generate

    cd sites/my-site
    swift run

Arc will serve the content immediately after generation.

## Adding a New Service (Server App)

Server apps are Hummingbird-based services with their own `Package.swift` in `sites/<app-name>/Web/`.

### 1) Create the service

Create a new Swift package:

    sites/my-service/
    └── Web/
        ├── Package.swift
        └── Sources/

Your package should produce a release binary (e.g. `MyServiceWeb`) that can be started by Arc.

### 2) Build the service

    cd sites/my-service/Web
    swift build -c release

### 3) Add to `Arc.swift`

    .service(
        name: "my-service",
        domain: "my-service.localhost",
        port: 8100,
        process: .process(
            workingDir: "sites/my-service/Web/",
            executable: ".build/arm64-apple-macosx/release/MyServiceWeb"
        )
    )

If you’re on Intel, the executable path is typically:

    .build/x86_64-apple-macosx/release/MyServiceWeb

### 4) Run with Arc

    arc run

Arc will start and watch the binary for changes.

## Adding a New App

Apps live in `apps/` and typically represent design or product artifacts. They are not automatically served by Arc. When an app becomes a service or static site, move it into `sites/` and register it in `Arc.swift`.

Suggested layout:

    apps/my-app/
    ├── PRD.md
    └── Notes.md

## Adding a New Embedded Project

Embedded projects live in `embedded/`. These are separate from Arc and typically build with the Embedded Swift toolchain.

Suggested layout:

    embedded/my-device/
    ├── Package.swift
    ├── Sources/
    └── README.md

Document hardware, flashing steps, and required environment variables in the project `README.md`.

## File Watching and Reloads

Arc watches:

- `Arc.swift` for configuration changes
- service binaries in `sites/*/Web/.build/**/release/`
- static site `.output/` directories

To trigger a reload:

- rebuild the service binary
- regenerate the static site

Arc will restart services or re-serve pages automatically.

## Best Practices

- **Swift API Design**: Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- **Logging**: Use `swift-log` consistently and avoid custom logging wrappers.
- **Formatting**: Run `swift format` before committing.
- **Concurrency**: Keep strict concurrency checks enabled.
- **Doc Comments**: Document public APIs and important behavior.

## Related Tutorials

- <doc:GettingStarted> — Set up Arc and run the server locally.
- <doc:RunServerLocally> — Build tooling and run the server end-to-end.
- <doc:CreateStaticSite> — Create and register a static site.
- <doc:CreateService> — Create and register a service.
- <doc:CreateApp> — Define an app workflow and promote it into `sites/`.
- <doc:EmbeddedWorkflow> — Organize embedded projects under `embedded/`.
- <doc:Configuration> — Configure `Arc.swift` properly.

## External Guides

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [Swift Server Guides](https://www.swift.org/server/)
- [Hummingbird Documentation](https://docs.hummingbirdproject.io/)
- [Swift Logging](https://github.com/apple/swift-log)
- [Swift Package Manager](https://www.swift.org/package-manager/)

## Common Workflows

### Static Site Workflow

1. Update site content in `Sources/`.
2. Run `swift run` to regenerate `.output`.
3. Refresh the browser.

### Service Workflow

1. Change service code.
2. Run `swift build -c release`.
3. Arc restarts the process automatically.

### Configuration Workflow

1. Update `Arc.swift`.
2. Save the file.
3. Arc reloads configuration automatically.

---

If you need a quick start, use the Xcode workspace and the preconfigured Arc scheme for a guided workflow.