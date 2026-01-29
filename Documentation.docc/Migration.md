# Migration Guide: From Pkl to Swift Manifests

@Metadata {
    @PageKind(article)
    @PageColor(blue)
}

This guide helps you migrate your existing `config.pkl` files to the new Swift-based `ArcManifest.swift` format.

---

## Quick Comparison

| Aspect | Pkl | Swift Manifest |
|--------|-----|----------------|
| **File Name** | `config.pkl` | `ArcManifest.swift` |
| **Syntax** | Pkl DSL | Swift |
| **Dependencies** | Pkl CLI + Runtime | Swift toolchain only |
| **Validation** | Runtime constraints | Compile-time + runtime |
| **IDE Support** | Limited | Full Xcode support |
| **Type Safety** | Strong | Strong |

---

## Basic Migration Examples

### Example 1: Simple Static Site

**Pkl (config.pkl):**
```pkl
amends "/opt/homebrew/share/arc/Arc_ArcCLI.bundle/ArcConfiguration.pkl"

processName = "my-server"

sites {
  new StaticSite {
    name = "portfolio"
    domain = "example.com"
    outputPath = "static/portfolio/.output"
  }
}
```

**Swift (ArcManifest.swift):**
```swift
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
```

---

### Example 2: Service (App) Site

**Pkl:**
```pkl
sites {
  new AppSite {
    name = "guest-list"
    domain = "guest-list.example.com"
    port = 8000
    process {
      workingDir = "apps/guest-list/Web/"
      executable = ".build/arm64-apple-macosx/release/GuestListWeb"
    }
  }
}
```

**Swift:**
```swift
import ArcDescription

let config = ArcConfiguration(
    sites: .init(
        services: [
            .init(
                name: "guest-list",
                domain: "guest-list.example.com",
                port: 8000,
                process: .init(
                    workingDir: "apps/guest-list/Web/",
                    executable: ".build/arm64-apple-macosx/release/GuestListWeb"
                )
            )
        ],
        pages: []
    )
)
```

---

### Example 3: Cloudflare Tunnel

**Pkl:**
```pkl
cloudflare {
  enabled = true
  tunnelName = "maclong-tunnel"
  tunnelUUID = "3787b929-d4d6-41c8-9227-4b427faa15c4"
}
```

**Swift:**
```swift
cloudflare: .init(
    enabled: true,
    tunnelName: "maclong-tunnel",
    tunnelUUID: "3787b929-d4d6-41c8-9227-4b427faa15c4"
)
```

---

### Example 4: SSH Configuration

**Pkl:**
```pkl
ssh {
    enabled = true
    domain = "ssh.maclong.dev"
}
```

**Swift:**
```swift
ssh: .init(
    enabled: true,
    domain: "ssh.maclong.dev"
)
```

---

## Complete Real-World Migration

### Original config.pkl:

```pkl
amends "/opt/homebrew/share/arc/Arc_ArcCLI.bundle/ArcConfiguration.pkl"

processName = "calm-machine"

sites {
  new StaticSite {
    name = "portfolio"
    domain = "maclong.dev"
    outputPath = "static/portfolio/.output"
  }
  new AppSite {
    name = "guest-list"
    domain = "guest-list.maclong.dev"
    port = 8000
    process {
      workingDir = "apps/guest-list/Web/"
      executable = ".build/arm64-apple-macosx/release/GuestListWeb"
    }
  }
}

cloudflare {
  enabled = true
  tunnelName = "maclong-tunnel"
  tunnelUUID = "3787b929-d4d6-41c8-9227-4b427faa15c4"
}

ssh {
    enabled = true
    domain = "ssh.maclong.dev"
}
```

### Migrated ArcManifest.swift:

```swift
import ArcDescription

let config = ArcConfiguration(
    processName: "calm-machine",
    sites: .init(
        services: [
            .init(
                name: "guest-list",
                domain: "guest-list.maclong.dev",
                port: 8000,
                process: .init(
                    workingDir: "apps/guest-list/Web/",
                    executable: ".build/arm64-apple-macosx/release/GuestListWeb"
                )
            )
        ],
        pages: [
            .init(
                name: "portfolio",
                domain: "maclong.dev",
                outputPath: "static/portfolio/.output"
            )
        ]
    ),
    cloudflare: .init(
        enabled: true,
        tunnelName: "maclong-tunnel",
        tunnelUUID: "3787b929-d4d6-41c8-9227-4b427faa15c4"
    ),
    ssh: .init(
        enabled: true,
        domain: "ssh.maclong.dev"
    )
)
```

---

## Key Differences

### 1. Terminology Changes

| Pkl | Swift |
|-----|-------|
| `AppSite` | `ServiceSite` (via `services:` array) |
| `StaticSite` | `StaticSite` (via `pages:` array) |
| `sites { ... }` | `sites: .init(services: [...], pages: [...])` |

### 2. Nesting Structure

**Pkl uses implicit blocks:**
```pkl
sites {
  new AppSite { ... }
  new StaticSite { ... }
}
```

**Swift uses explicit initialization:**
```swift
sites: .init(
    services: [ /* ServiceSite instances */ ],
    pages: [ /* StaticSite instances */ ]
)
```

### 3. Amends/Inheritance

**Pkl:**
```pkl
amends "/path/to/base.pkl"
```

**Swift:**
No inheritance needed! All defaults are built into the types. Just import `ArcDescription` and you're ready.

---

## Advanced Features

### Environment Variables

**Pkl:**
```pkl
// Not directly supported - requires external tools
```

**Swift:**
```swift
import Foundation
import ArcDescription

let isDev = ProcessInfo.processInfo.environment["ENV"] == "development"
let dbHost = ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost"

let config = ArcConfiguration(
    proxyPort: isDev ? 8080 : 80,
    sites: .init(
        services: [
            .init(
                name: "api",
                domain: "api.example.com",
                port: 8000,
                process: .init(
                    workingDir: "apps/api/",
                    executable: ".build/release/API",
                    env: [
                        "DATABASE_URL": "postgresql://\(dbHost):5432/db"
                    ]
                )
            )
        ]
    )
)
```

### Conditional Logic

**Swift advantages:**
```swift
import ArcDescription

// Platform-specific paths
#if arch(arm64)
let executablePath = ".build/arm64-apple-macosx/release/App"
#else
let executablePath = ".build/x86_64-apple-macosx/release/App"
#endif

// Environment-based configuration
let isProduction = ProcessInfo.processInfo.environment["ENV"] == "production"

let config = ArcConfiguration(
    healthCheckInterval: isProduction ? 60 : 30,
    sites: .init(
        services: [
            .init(
                name: "app",
                domain: isProduction ? "app.com" : "app.local",
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

---

## Migration Checklist

- [ ] Create `ArcManifest.swift` in your project root
- [ ] Import `ArcDescription` at the top
- [ ] Convert `processName` (if set)
- [ ] Convert all `AppSite` entries to `ServiceSite` in `services:` array
- [ ] Convert all `StaticSite` entries to the `pages:` array
- [ ] Convert `cloudflare` configuration (if enabled)
- [ ] Convert `ssh` configuration (if enabled)
- [ ] Remove `amends` line (not needed in Swift)
- [ ] Test with `arc run --config ArcManifest.swift`
- [ ] Remove old `config.pkl` once verified

---

## Common Pitfalls

### 1. Missing Import

❌ **Wrong:**
```swift
let config = ArcConfiguration(...)
```

✅ **Correct:**
```swift
import ArcDescription

let config = ArcConfiguration(...)
```

### 2. Wrong Array Names

❌ **Wrong:**
```swift
sites: .init(
    apps: [...],      // Wrong!
    static: [...]     // Wrong!
)
```

✅ **Correct:**
```swift
sites: .init(
    services: [...],  // Correct!
    pages: [...]      // Correct!
)
```

### 3. Forgetting Process Config

❌ **Wrong:**
```swift
.init(
    name: "app",
    domain: "example.com",
    port: 8000,
    executable: "path/to/app"  // Wrong! No direct executable parameter
)
```

✅ **Correct:**
```swift
.init(
    name: "app",
    domain: "example.com",
    port: 8000,
    process: .init(
        workingDir: "apps/app/",
        executable: "path/to/app"
    )
)
```

---

## Testing Your Migration

1. **Validate syntax:**
   ```bash
   cd /path/to/your/project
   swift ArcManifest.swift  # Should compile without errors
   ```

2. **Test with arc:**
   ```bash
   arc run --config ArcManifest.swift
   ```

3. **Verify all sites load:**
   ```bash
   arc status
   ```

4. **Check config is recognized:**
   ```bash
   arc doctor
   ```

---

## All Available Options

Here's a complete reference of all available configuration options:

```swift
import ArcDescription

let config = ArcConfiguration(
    // Proxy Configuration
    proxyPort: 8080,                          // Port for proxy server
    logDir: "~/Library/Logs/arc",             // Log file directory
    baseDir: nil,                             // Base directory (auto-detected if nil)
    healthCheckInterval: 30,                  // Health check interval (seconds)
    version: "V.2.0.0",                       // Server version string
    region: nil,                              // Optional region identifier
    processName: nil,                         // Optional process name
    
    // Sites
    sites: .init(
        services: [
            .init(
                name: "service-name",         // Unique name
                domain: "example.com",        // Routing domain
                port: 8000,                   // Service port
                healthPath: "/health",        // Health check endpoint
                process: .init(
                    workingDir: "apps/service/",
                    executable: ".build/release/Service",
                    command: nil,             // Alternative to executable
                    args: nil,                // Command arguments
                    env: nil                  // Environment variables
                ),
                watchTargets: nil             // Optional watch paths
            )
        ],
        pages: [
            .init(
                name: "site-name",            // Unique name
                domain: "example.com",        // Routing domain
                outputPath: "static/.output", // Static file path
                watchTargets: nil             // Optional watch paths
            )
        ]
    ),
    
    // Cloudflare Tunnel
    cloudflare: .init(
        enabled: false,
        cloudflaredPath: "/opt/homebrew/bin/cloudflared",
        tunnelName: nil,
        tunnelUUID: nil
    ),
    
    // SSH Access
    ssh: .init(
        enabled: false,
        domain: nil,
        port: 22
    ),
    
    // File Watching
    watch: .init(
        enabled: true,
        watchConfig: true,                    // Watch manifest file
        followSymlinks: false,
        debounceMs: 300,
        cooldownMs: 1000
    )
)
```

---

## Getting Help

- **Examples:** Check the `examples/` directory for reference implementations
- **Documentation:** Run `swift package generate-documentation` in the arc project
- **Issues:** Report migration problems on GitHub

---

## Benefits of Swift Manifests

✅ **No External Dependencies** - Just the Swift toolchain  
✅ **Better IDE Support** - Full autocomplete and refactoring  
✅ **Type Safety** - Catch errors at compile time  
✅ **Native Swift** - No context switching  
✅ **Dynamic Configuration** - Use environment variables and logic  
✅ **Easier Debugging** - Standard Swift error messages  
✅ **Version Control** - Better diffs in Git  

---

Happy migrating! 🚀