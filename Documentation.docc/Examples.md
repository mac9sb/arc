# Arc Swift Manifest Examples

@Metadata {
    @PageKind(article)
    @PageColor(blue)
}

This section contains example `ArcManifest.swift` files demonstrating various configuration patterns for the Arc server proxy.

## Overview

Arc has migrated from Pkl-based configuration to native Swift manifests. These examples show you how to configure Arc using Swift's type-safe, compile-time validated configuration system.

---

## Examples

### 1. BasicExample.swift - Minimal Configuration

The simplest possible Arc configuration with a single static site.

**Use this when:**
- You're just getting started with Arc
- You only need to serve static files
- You want to understand the minimum required configuration

**Key features:**
- Single static site
- Minimal configuration options
- Good starting point for learning

---

### 2. MultiServiceExample.swift - Typical Production Setup

A realistic configuration with multiple services and static sites working together.

**Use this when:**
- You have both backend services and static sites
- You need multiple domains
- You're setting up a production-like environment

**Key features:**
- Multiple backend services (ports 8000-8002)
- Multiple static sites
- Cloudflare Tunnel integration
- Environment variables in process config
- Watch targets for hot-reload

---

### 3. FullFeaturedExample.swift - Complete Reference

Demonstrates every available configuration option in `ArcDescription`.

**Use this when:**
- You need advanced features
- You want to see all available options
- You're migrating complex Pkl configs

**Key features:**
- All configuration options shown
- Environment-based dynamic configuration
- Process environment variables
- Custom health check paths
- SSH configuration
- Watch configuration
- Multiple process execution methods (executable vs command)

---

## Quick Start

1. **Choose an example** that matches your needs from the Examples directory
2. **Create** `ArcManifest.swift` in your project root based on the example
3. **Customize** the configuration for your project
4. **Run Arc** with your manifest:
   ```bash
   arc run
   # or specify explicitly:
   arc run --config ArcManifest.swift
   ```

---

## Example Files

Each example demonstrates:
- Complete, working configuration syntax
- Specific use cases and patterns
- Commented explanations of features

---

## Migration Guide

If you're migrating from Pkl configuration files, see <doc:Migration> for:
- Side-by-side Pkl vs Swift comparisons
- Common pitfalls and how to avoid them
- Complete migration checklist
- Testing strategies

---

## Configuration Reference

### ArcConfiguration

The top-level configuration object that defines your entire Arc setup.

```swift
import ArcDescription

let config = ArcConfiguration(
    processName: String?,              // Optional process identifier
    sites: Sites,                      // Site configurations
    cloudflare: CloudflareConfig?,     // Cloudflare Tunnel config
    ssh: SshConfig?,                   // SSH access config
    watch: WatchConfig,                // File watching config
    // ... and more
)
```

### Sites

Groups your services (backend apps) and pages (static sites).

```swift
sites: .init(
    services: [ServiceSite],  // Backend/full-stack applications
    pages: [StaticSite]       // Static HTML/CSS/JS sites
)
```

### ServiceSite (formerly AppSite)

Configuration for a backend service or full-stack application.

```swift
.init(
    name: String,              // Unique identifier
    domain: String,            // Routing domain
    port: Int,                 // Port the service listens on
    healthPath: String,        // Health check endpoint (default: "/health")
    process: ProcessConfig,    // How to run the process
    watchTargets: [String]?    // Optional paths to watch for changes
)
```

### StaticSite

Configuration for static file serving.

```swift
.init(
    name: String,              // Unique identifier
    domain: String,            // Routing domain
    outputPath: String,        // Path to static files (relative to baseDir)
    watchTargets: [String]?    // Optional paths to watch for rebuilds
)
```

### ProcessConfig

Defines how to execute a service.

```swift
.init(
    workingDir: String,        // Working directory (relative to baseDir)
    executable: String?,       // Path to executable (option 1)
    command: String?,          // Command to run (option 2)
    args: [String]?,           // Arguments for command
    env: [String: String]?     // Environment variables
)
```

---

## Advanced Patterns

### Dynamic Configuration with Environment Variables

```swift
import Foundation
import ArcDescription

let isDev = ProcessInfo.processInfo.environment["ENV"] == "development"
let apiKey = ProcessInfo.processInfo.environment["API_KEY"] ?? ""

let config = ArcConfiguration(
    proxyPort: isDev ? 8080 : 80,
    sites: .init(
        services: [
            .init(
                name: "api",
                domain: isDev ? "api.local" : "api.example.com",
                port: 8000,
                process: .init(
                    workingDir: "apps/api/",
                    executable: ".build/release/API",
                    env: ["API_KEY": apiKey]
                )
            )
        ]
    )
)
```

### Platform-Specific Configuration

```swift
#if arch(arm64)
let executablePath = ".build/arm64-apple-macosx/release/App"
#else
let executablePath = ".build/x86_64-apple-macosx/release/App"
#endif

let config = ArcConfiguration(
    sites: .init(
        services: [
            .init(
                name: "app",
                domain: "example.com",
                port: 8000,
                process: .init(
                    workingDir: "apps/app/",
                    executable: executablePath
                )
            )
        ]
    )
)
```

### Shared Configuration with Swift Functions

```swift
import ArcDescription

func createService(name: String, port: Int) -> ServiceSite {
    .init(
        name: name,
        domain: "\(name).example.com",
        port: port,
        process: .init(
            workingDir: "apps/\(name)/Web/",
            executable: ".build/release/\(name.capitalized)Web"
        )
    )
}

let config = ArcConfiguration(
    sites: .init(
        services: [
            createService(name: "api", port: 8000),
            createService(name: "admin", port: 8001),
            createService(name: "worker", port: 8002)
        ]
    )
)
```

---

## Validation

Arc validates your configuration at:

1. **Compile time** - Swift type system catches errors
2. **Load time** - Arc validates paths, ports, and constraints
3. **Runtime** - Health checks ensure services are working

Common validations:
- Unique site names
- Unique ports for services
- Valid port ranges (1024-65535)
- Executable/output path existence

---

## Testing Your Configuration

```bash
# Validate syntax (compile-time check)
swift ArcManifest.swift

# Test with Arc
arc run --config ArcManifest.swift

# Check status
arc status

# Run diagnostics
arc doctor

# View logs
arc logs
```

---

## Troubleshooting

### "Module 'ArcDescription' not found"

**Solution:** Ensure Arc is properly built:
```bash
cd tooling/arc
swift build -c release
```

### "Cannot find 'config' in scope"

**Solution:** Make sure you have `let config = ArcConfiguration(...)` in your manifest.

### "Executable not found"

**Solution:** Build your service first:
```bash
cd apps/your-service/Web
swift build -c release
```

### Port conflicts

**Solution:** Ensure each service uses a unique port. Check with:
```bash
lsof -i :8000  # Check if port 8000 is in use
```

---

## Best Practices

1. **Use descriptive names** - Service names should be clear and meaningful
2. **Group related services** - Use consistent port ranges (e.g., 8000-8099 for APIs)
3. **Set environment variables** - Don't hardcode secrets in manifests
4. **Use watch targets** - Enable hot-reload for faster development
5. **Test incrementally** - Start with one service, then add more
6. **Version control** - Commit your `ArcManifest.swift` to git

---

## Additional Resources

- **Migration Guide:** <doc:Migration>
- **Configuration Tutorial:** <doc:Configuration>
- **Getting Started:** <doc:GettingStarted>

---

## See Also

- <doc:Migration> - Migrating from Pkl to Swift manifests
- <doc:Configuration> - Configuration tutorial
- <doc:GettingStarted> - Getting started with Arc

---

Happy configuring! 🚀