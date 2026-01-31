# Arc

Arc is a local development server management tool that provides a unified proxy for managing multiple static sites and dynamic applications.

## Overview

Arc simplifies local development by providing:

- **Unified Proxy Server**: Single entry point for all your local projects
- **Automatic Process Management**: Start, stop, and monitor multiple services
- **File Watching**: Automatic reloading when configuration changes
- **Cloudflare Tunnel Integration**: Expose local services via Cloudflare tunnels
- **Health Monitoring**: Track the status of all your services

## Getting Started

See the <doc:GettingStarted> tutorial to set up your first Arc project.

## Configuration

Arc uses a Swift manifest named `ArcManifest.swift` for configuration. See the <doc:Configuration> tutorial for details on setting up your manifest file.

### Swift Manifests (New)

Arc now uses native Swift for configuration . This provides:

- **Type Safety**: Catch errors at compile time
- **No External Dependencies**: Just the Swift toolchain
- **Better IDE Support**: Full autocomplete and refactoring
- **Dynamic Configuration**: Use environment variables and Swift logic


For complete configuration schema documentation, see ``ArcConfiguration``.

## Commands

- `arc run` - Start the Arc server
- `arc stop` - Stop running Arc servers
- `arc status` - Check the status of running servers
- `arc logs` - View server logs
- `arc doctor` - Run diagnostics and health checks

See <doc:Commands> for detailed command documentation.

## Architecture

Arc consists of several modules:

- **ArcCLI**: Command-line interface and argument parsing
- **ArcCore**: Core configuration and process management
- **ArcDescription**: Swift manifest type definitions
- **ArcServer**: HTTP server and proxy functionality

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:Configuration>
- <doc:Examples>
- <doc:ServerWorkflow>
- <doc:RunServerLocally>
- <doc:CreateStaticSite>
- <doc:CreateService>
- <doc:CreateApp>
- <doc:EmbeddedWorkflow>



### Deployment

- <doc:Deployment>

### Implementation

- <doc:SwiftManifestImplementation>
- <doc:ArcManifest-PRD>

### Reference

- <doc:Commands>
- ``ArcConfiguration``
- ``ServiceSite``
- ``StaticSite``
