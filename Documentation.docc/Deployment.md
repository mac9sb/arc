# Deploying Arc to Production

@Metadata {
    @PageKind(article)
    @PageColor(orange)
}

A comprehensive guide for deploying Arc and ArcDescription to production environments.

## Overview

Arc requires the Swift toolchain and the ArcDescription module to load Swift manifests at runtime. This guide covers deployment strategies, installation paths, and troubleshooting.

---

## Prerequisites

- Swift 6.2+ toolchain installed on production server
- Arc built in release mode
- ArcManifest.swift configuration file

---

## Deployment Strategies

### Strategy 1: System-Wide Installation (Recommended)

Install Arc and ArcDescription to system paths for easy access.

#### Installation Steps

1. **Build Arc in release mode:**
   ```bash
   cd tooling/arc
   swift build -c release
   ```

2. **Install the arc executable:**
   ```bash
   sudo install -m 755 .build/release/arc /usr/local/bin/arc
   ```

3. **Install ArcDescription module and library:**
   ```bash
   # Create installation directory
   sudo mkdir -p /usr/local/lib/arc
   
   # Copy module files
   sudo cp -R .build/release/ArcDescription.swiftmodule /usr/local/lib/arc/
   
   # Copy library
   sudo cp .build/release/libArcDescription.a /usr/local/lib/arc/
   ```

4. **Verify installation:**
   ```bash
   arc --version
   which arc
   # Should output: /usr/local/bin/arc
   ```

#### Module Search Behavior

Arc will automatically find ArcDescription in:
- `/usr/local/bin/../lib/arc/` (relative to executable)
- `/usr/local/lib/arc/` (standard library path)

---

### Strategy 2: Bundled Installation

Bundle Arc with ArcDescription for relocatable installation.

#### Installation Steps

1. **Create bundle directory:**
   ```bash
   mkdir -p arc-bundle/bin
   mkdir -p arc-bundle/lib
   ```

2. **Copy files:**
   ```bash
   cp .build/release/arc arc-bundle/bin/
   cp -R .build/release/ArcDescription.swiftmodule arc-bundle/lib/
   cp .build/release/libArcDescription.a arc-bundle/lib/
   ```

3. **Deploy bundle:**
   ```bash
   # Copy entire bundle to production
   scp -r arc-bundle/ user@server:/opt/arc/
   
   # Create symlink for easy access
   ssh user@server 'sudo ln -s /opt/arc/bin/arc /usr/local/bin/arc'
   ```

#### Module Search Behavior

Arc searches relative to its executable location:
- `<arc-location>/../lib/`
- `<arc-location>/../share/arc/lib/`

---

### Strategy 3: Homebrew Installation (macOS)

Use Homebrew for macOS deployments.

#### Formula Structure

```ruby
class Arc < Formula
  desc "Local development server management tool"
  homepage "https://github.com/yourusername/arc"
  url "https://github.com/yourusername/arc/archive/v2.0.0.tar.gz"
  sha256 "..."

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    
    bin.install ".build/release/arc"
    
    # Install ArcDescription module
    lib.install ".build/release/libArcDescription.a"
    (lib/"arc").install Dir[".build/release/ArcDescription.swiftmodule"]
  end

  test do
    system "#{bin}/arc", "--version"
  end
end
```

---

### Strategy 4: Docker Deployment

Deploy Arc in a container with Swift runtime.

#### Dockerfile

```dockerfile
FROM swift:6.2

WORKDIR /arc

# Copy Arc source
COPY . .

# Build Arc
RUN swift build -c release

# Install system-wide
RUN install -m 755 .build/release/arc /usr/local/bin/arc && \
    mkdir -p /usr/local/lib/arc && \
    cp -R .build/release/ArcDescription.swiftmodule /usr/local/lib/arc/ && \
    cp .build/release/libArcDescription.a /usr/local/lib/arc/

# Copy project files
WORKDIR /project
COPY ArcManifest.swift .

# Run Arc
CMD ["arc", "run"]
```

#### Build and Run

```bash
docker build -t arc-server .
docker run -d --name arc -p 8080:8080 arc-server
```

---

## Installation Verification

### Check Arc Installation

```bash
# Verify arc is in PATH
which arc

# Check version
arc --version

# Verify it runs
arc --help
```

### Check ArcDescription Module

```bash
# Test manifest loading
cd /path/to/project
arc run --config ArcManifest.swift
```

If you see `ArcDescription module not found`, the module is not in the search path.

---

## Module Search Paths

Arc searches for ArcDescription in the following order:

1. **Relative to executable:**
   - `<arc-dir>/`
   - `<arc-dir>/../lib/`
   - `<arc-dir>/../lib/arc/`
   - `<arc-dir>/../share/arc/`
   - `<arc-dir>/../share/arc/lib/`

2. **Development builds:**
   - `.build/debug/`
   - `.build/release/`
   - `.build/arm64-apple-macosx/debug/`
   - `.build/arm64-apple-macosx/release/`
   - `.build/x86_64-apple-macosx/debug/`
   - `.build/x86_64-apple-macosx/release/`

3. **System paths:**
   - `/usr/local/lib/arc/`
   - `/opt/homebrew/lib/arc/`
   - `/opt/arc/lib/`

---

## Environment-Specific Configuration

### Development Environment

Keep Arc in development mode for hot-reload:

```swift
import Foundation
import ArcDescription

let isDev = ProcessInfo.processInfo.environment["ENV"] == "development"

let config = ArcConfiguration(
    proxyPort: isDev ? 8080 : 80,
    healthCheckInterval: isDev ? 10 : 60,
    sites: .init(
        services: [
            .init(
                name: "api",
                domain: isDev ? "api.localhost" : "api.example.com",
                port: 8000,
                process: .init(
                    workingDir: "apps/api/",
                    executable: isDev ? ".build/debug/API" : ".build/release/API"
                )
            )
        ]
    )
)
```

### Production Environment

Use environment variables for sensitive data:

```swift
import Foundation
import ArcDescription

let apiKey = ProcessInfo.processInfo.environment["API_KEY"] ?? ""
let dbHost = ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost"

let config = ArcConfiguration(
    processName: "production-server",
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
                        "API_KEY": apiKey,
                        "DATABASE_URL": "postgresql://\(dbHost):5432/db"
                    ]
                )
            )
        ]
    )
)
```

---

## Troubleshooting

### "ArcDescription module not found"

**Symptoms:**
```
ArcDescription module not found.

To fix this, build Arc first:
  cd tooling/arc
  swift build -c release
```

**Solutions:**

1. **Check module installation:**
   ```bash
   # Look for module files
   find /usr/local/lib -name "ArcDescription.swiftmodule"
   find /opt -name "ArcDescription.swiftmodule"
   ```

2. **Verify module is in search path:**
   ```bash
   # Check relative to arc executable
   ls -la $(dirname $(which arc))/../lib/arc/
   ```

3. **Reinstall ArcDescription:**
   ```bash
   cd tooling/arc
   swift build -c release
   sudo cp -R .build/release/ArcDescription.swiftmodule /usr/local/lib/arc/
   sudo cp .build/release/libArcDescription.a /usr/local/lib/arc/
   ```

---

### "Swift manifest compilation failed"

**Symptoms:**
```
error: no such module 'ArcDescription'
import ArcDescription
       ^
```

**Solutions:**

1. **Ensure manifest has correct import:**
   ```swift
   import ArcDescription  // Required first line
   
   let config = ArcConfiguration(...)
   ```

2. **Verify Swift is in PATH:**
   ```bash
   which swift
   swift --version
   ```

3. **Check manifest syntax:**
   ```bash
   # Try compiling manually
   cd /path/to/project
   swift ArcManifest.swift
   ```

---

### Permission Errors

**Symptoms:**
```
Permission denied when accessing /var/log/arc
```

**Solutions:**

1. **Create log directory with proper permissions:**
   ```bash
   sudo mkdir -p /var/log/arc
   sudo chown $(whoami) /var/log/arc
   ```

2. **Or use user-specific log directory:**
   ```swift
   let config = ArcConfiguration(
       logDir: "~/Library/Logs/arc"  // User home directory
   )
   ```

---

### Port Conflicts

**Symptoms:**
```
precondition failed: Service ports must be unique
```

**Solutions:**

1. **Check running processes:**
   ```bash
   lsof -i :8080
   lsof -i :8000
   ```

2. **Update ArcManifest.swift with unique ports:**
   ```swift
   services: [
       .init(name: "api", domain: "api.local", port: 8000, ...),
       .init(name: "admin", domain: "admin.local", port: 8001, ...)  // Unique!
   ]
   ```

---

## Security Considerations

### File Permissions

Set appropriate permissions for Arc files:

```bash
# Executable should be readable and executable by all
chmod 755 /usr/local/bin/arc

# Library files should be readable by all
chmod 644 /usr/local/lib/arc/libArcDescription.a

# Module files should be readable by all
chmod -R 644 /usr/local/lib/arc/ArcDescription.swiftmodule/
```

### Manifest Security

**Never commit secrets to ArcManifest.swift:**

❌ **Bad:**
```swift
env: [
    "API_KEY": "secret-key-12345"  // Don't do this!
]
```

✅ **Good:**
```swift
env: [
    "API_KEY": ProcessInfo.processInfo.environment["API_KEY"] ?? ""
]
```

Then provide at runtime:
```bash
export API_KEY="secret-key-12345"
arc run
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Swift 6.2+ installed on production server
- [ ] Arc built in release mode (`swift build -c release`)
- [ ] ArcManifest.swift tested locally
- [ ] All services build successfully
- [ ] Environment variables documented

### Installation

- [ ] Arc executable installed to PATH
- [ ] ArcDescription module installed
- [ ] ArcDescription library installed
- [ ] Module search paths verified
- [ ] Installation tested with sample manifest

### Configuration

- [ ] ArcManifest.swift created in project root
- [ ] Ports configured (unique and > 1024)
- [ ] Service executables built and paths correct
- [ ] Static site output paths correct
- [ ] Health check endpoints verified
- [ ] Environment variables set

### Verification

- [ ] `arc run` starts without errors
- [ ] `arc status` shows all services
- [ ] All services respond to health checks
- [ ] Static sites serve correctly
- [ ] Logs are being written
- [ ] Hot-reload works (if enabled)

### Production

- [ ] Cloudflare tunnel configured (if needed)
- [ ] SSH access configured (if needed)
- [ ] Monitoring set up
- [ ] Backup strategy in place
- [ ] Rollback plan documented

---

## Version Compatibility

Arc and ArcDescription must be compatible versions:

| Arc Version | ArcDescription Version | Swift Version |
|-------------|------------------------|---------------|
| 2.0.x       | 2.0.x                  | 6.2+          |

**Important:** Always deploy matching versions of Arc and ArcDescription. Mixing versions may cause runtime errors.

---

## Upgrading Arc

### Minor Version Update

```bash
# 1. Backup current installation
sudo cp /usr/local/bin/arc /usr/local/bin/arc.backup

# 2. Build new version
cd tooling/arc
git pull
swift build -c release

# 3. Install new version
sudo install -m 755 .build/release/arc /usr/local/bin/arc
sudo cp -R .build/release/ArcDescription.swiftmodule /usr/local/lib/arc/
sudo cp .build/release/libArcDescription.a /usr/local/lib/arc/

# 4. Verify
arc --version

# 5. Restart Arc
arc stop
arc run
```

### Rollback

```bash
# Restore backup
sudo mv /usr/local/bin/arc.backup /usr/local/bin/arc
arc --version
```

---

## See Also

- <doc:Examples> - Example configurations
- <doc:Migration> - Migrating from Pkl
- <doc:GettingStarted> - Getting started guide
- ``ArcConfiguration`` - Configuration reference