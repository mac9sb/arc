# Swift Manifest Implementation Status

@Metadata {
    @PageKind(article)
    @PageColor(green)
}

This document tracks the implementation status of the Swift manifest system for Arc configuration.

## Overview

The Swift manifest system replaces the previous previous configuration with a native Swift approach, providing type safety, better IDE support, and zero external dependencies.

## Implementation Status

### ✅ Completed Components

#### 1. ArcDescription Module
**Status:** Complete  
**Location:** `Sources/ArcDescription/ArcDescription.swift`

The core type library that users import in their manifests:

- `ArcConfiguration` - Top-level configuration with all settings
- `Sites` - Groups services and pages
- `ServiceSite` - Backend/full-stack service configuration
- `StaticSite` - Static page configuration
- `ProcessConfig` - Process execution details
- `WatchConfig` - File watching and hot-reload
- `CloudflareConfig` - Cloudflare Tunnel integration
- `SshConfig` - SSH access configuration

**Features:**
- Full `Codable` support for JSON serialization
- `Sendable` conformance for concurrency safety
- `Hashable` for comparison operations
- `Identifiable` where appropriate
- Comprehensive initializers with sensible defaults
- Public API with proper access control

#### 2. ArcManifestLoader
**Status:** Complete  
**Location:** `Sources/ArcCore/ArcManifestLoader.swift`

Compiles and loads Swift manifest files at runtime:

**Key Features:**
- On-the-fly Swift compilation using the system toolchain
- Automatic module search across development and production paths
- Temporary runner generation for JSON export
- Proper error handling and diagnostics
- `baseDir` inference when not specified

**How It Works:**
1. Resolves manifest path (file or directory with `ArcManifest.swift`)
2. Generates temporary runner that imports manifest
3. Searches for `ArcDescription` module in build outputs
4. Compiles with `-I` and `-L` flags for module linking
5. Executes and captures JSON output
6. Decodes into `ArcConfiguration`

**Search Strategy:**
- Runtime paths relative to `arc` executable
- Development build outputs (`.build/debug`, `.build/release`)
- Multi-architecture support (arm64, x86_64)

#### 3. ArcConfig Wrapper
**Status:** Complete  
**Location:** `Sources/ArcCore/ArcConfig.swift`

Runtime configuration wrapper around `ArcConfiguration`:

**Features:**
- Computed properties for common config values
- Site enumeration (discriminated union of static/app sites)
- Helper methods (`healthURL()`, `baseURL()`)
- Type aliases for backwards compatibility
- Conversion between `ArcConfiguration` and `ArcConfig`

#### 4. Backwards Compatibility Layer
**Status:** Complete  
**Location:** `Sources/ArcCore/ArcConfig+Loading.swift`

Preserves existing CLI call sites:

**Features:**
- `ModuleSource` shim for legacy API
- Multiple `loadFrom()` overload signatures
- Both sync and async variants
- Optional `configPath` parameter (ignored)

**Supported APIs:**
```swift
ArcConfig.loadFrom(path: String)
ArcConfig.loadFrom(path: String, configPath: URL?)
ArcConfig.loadFrom(source: ModuleSource)
ArcConfig.loadFrom(source: ModuleSource, configPath: URL?)
```

#### 5. CLI Integration
**Status:** Complete  
**Location:** All commands in `Sources/ArcCLI/Commands/`

All CLI commands successfully use the new loader:
- `StartCommand` - Loads manifest and starts services
- `StatusCommand` - Reads manifest for status display
- `DoctorCommand` - Validates manifest configuration
- `LogsCommand` - Uses manifest for log paths
- `MetricsCommand` - Reads manifest for metrics

#### 6. Hot-Reload Support
**Status:** Complete  
**Location:** `StartCommand.swift` file watcher integration

Manifest changes trigger automatic reload:
- File watcher monitors `ArcManifest.swift`
- Recompiles on changes
- Stops all processes
- Reloads configuration
- Restarts services with new config

---

### ⚠️ Remaining Work

#### 1. Validation Logic
**Priority:** High  
**Estimated Effort:** 2-4 hours

Add runtime validation in `ArcDescription` initializers:

**Needed Validations:**
- Port range (1024-65535)
- Unique site names across all sites
- Unique ports across all services
- Non-empty required strings (name, domain)
- Domain format validation (basic)
- Path existence checks (optional warnings)

**Implementation Approach:**
```swift
public init(name: String, domain: String, port: Int, process: ProcessConfig) {
    precondition(port > 1024 && port < 65536, "Port must be in range 1024-65535")
    precondition(!name.isEmpty, "Site name cannot be empty")
    precondition(!domain.isEmpty, "Domain cannot be empty")
    // ... validation logic
    self.name = name
    self.domain = domain
    self.port = port
    self.process = process
}
```

#### 2. Builder Pattern (Optional)
**Priority:** Medium  
**Estimated Effort:** 4-6 hours

Provide ergonomic configuration builders:

```swift
let config = ArcConfiguration.build {
    $0.processName = "server"
    $0.addService("api") {
        $0.domain = "api.local"
        $0.port = 8000
        $0.executable = ".build/release/API"
    }
    $0.addPage("site") {
        $0.domain = "site.local"
        $0.outputPath = "static/.output"
    }
}
```

#### 3. Enhanced Error Messages
**Priority:** Medium  
**Estimated Effort:** 2-3 hours

Improve diagnostics for common mistakes:

- "Module not found" → Suggest building Arc first
- "Compilation failed" → Show Swift errors with context
- "Invalid port" → Suggest available port range
- Missing executable → Suggest build command

#### 4. Production Installation Guide
**Priority:** High  
**Estimated Effort:** 2-3 hours (documentation)

Document deployment strategies:

- How to install `ArcDescription` module
- Bundling options for production
- Version compatibility guidelines
- Deployment checklist

#### 5. Comprehensive Testing
**Priority:** High  
**Estimated Effort:** 4-8 hours

Add test coverage:

- Valid manifest loading tests
- Invalid manifest error handling
- Validation edge cases
- Module search path resolution
- Multi-platform compatibility
- Integration tests with actual services

#### 6. DocC Documentation Enhancement
**Priority:** Medium  
**Estimated Effort:** 2-4 hours

Expand inline documentation:

- Add DocC comments to all public APIs
- Document parameters and return values
- Provide usage examples in comments
- Add See Also references
- Document throwing conditions

---

## Success Metrics

### Achieved ✅

1. **Zero external dependencies** - No `pkl-swift` or external CLI tools required
2. **Compile-Time Type Safety** - Swift's type system catches errors
3. **Full CLI Compatibility** - All commands work with new system
4. **Hot-Reload Working** - Config changes trigger automatic reload
5. **Development Workflow** - Seamless experience in Xcode

### In Progress ⏳

1. **Validation** - Need runtime constraint checking
2. **Documentation** - Examples complete, API docs need expansion
3. **Testing** - Core functionality works, need comprehensive tests

### Pending 📋

1. **Production Story** - Need deployment documentation
2. **Error UX** - Error messages could be more helpful
3. **Builder Pattern** - Would improve ergonomics

---


### For Users

1. ✅ Create `ArcManifest.swift` in project root
2. ✅ Import `ArcDescription`
3. ✅ Define `config` variable with `ArcConfiguration`
4. ✅ Run `arc run` (automatically detects new manifest)
5. ✅ Remove old `legacy config files`


### For Arc Development

1. ✅ Build Arc: `swift build -c release`
2. ✅ ArcDescription module built automatically
3. ✅ Loader finds module in `.build/release/`
4. ✅ No additional setup required

---

## Technical Decisions

### Why On-The-Fly Compilation?

**Alternatives Considered:**
1. Pre-compile manifests into binary
2. Use Swift's package manifest approach
3. Dynamic library loading
4. Interpreted configuration

**Chosen Approach:** On-the-fly compilation with `swift` command

**Rationale:**
- Mirrors `Package.swift` behavior (familiar to Swift developers)
- No separate build step required
- Full Swift language features available
- Type safety at load time
- Simple implementation
- Works in both development and production

**Trade-offs:**
- Requires Swift toolchain installed
- Slightly slower first load (cached thereafter)
- Need to locate ArcDescription module

### Module Discovery Strategy

**Why Multiple Search Paths?**

Development and production have different layouts:

**Development:**
- `.build/debug/` or `.build/release/`
- Multiple architectures in subdirectories
- Frequent rebuilds

**Production:**
- Relative to `arc` executable
- `/opt/homebrew/`, `/usr/local/`, etc.
- Stable installation paths

**Solution:** Search all likely locations, cache first found path.

### Type Design Decisions

#### Why Structs Over Classes?

- Value semantics prevent accidental mutation
- Better for `Codable` serialization
- Sendable conformance for concurrency
- Hashable/Equatable for free
- Performance benefits

#### Why Separate Sites.services and Sites.pages?

- Clear semantic distinction
- Type safety (can't mix service/page config)
- Better autocomplete in IDEs
- Matches mental model ("apps" vs "static sites")

#### Why Optional baseDir?

- Can infer from manifest location
- Most common case: manifest in project root
- Still allows explicit override if needed

---

## Future Enhancements

### Potential Features (Not Committed)

1. **Config Templates**
   ```swift
   let standardService = ServiceTemplate(
       healthPath: "/health",
       watchTargets: ["Sources/"]
   )
   ```

2. **Config Composition**
   ```swift
   let baseConfig = ArcConfiguration.base()
   let devConfig = baseConfig.with(proxyPort: 8080)
   ```

3. **Conditional Compilation**
   ```swift
   #if DEBUG
   let services = [devService]
   #else
   let services = [prodService]
   #endif
   ```

4. **Config Validation DSL**
   ```swift
   config.validate {
       $0.ports.areUnique()
       $0.names.areUnique()
       $0.executables.exist()
   }
   ```

---

## Timeline

### Phase 1: Core Implementation ✅ Complete
- ArcDescription types
- Manifest loader
- CLI integration
- Backwards compatibility

### Phase 2: Refinement ⏳ In Progress
- Example manifests ✅
- Validation logic ⚠️
- Error messages ⚠️

### Phase 3: Production Ready 📋 Upcoming
- Comprehensive testing
- Production deployment guide
- Performance optimization
- Documentation completion

---

## Contributing

To work on the Swift manifest system:

1. **Make changes** in `Sources/ArcDescription/`
2. **Rebuild:** `swift build -c release`
3. **Test:** Update `ArcManifest.swift` in root and run `arc run`
4. **Document:** Add DocC comments to public APIs
5. **Test:** Add tests in `Tests/ArcCoreTests/`

---

## See Also

- <doc:Examples> - Example manifest configurations
- <doc:ArcManifest-PRD> - Original product requirements
- ``ArcConfiguration`` - Configuration type reference