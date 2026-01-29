# Arc

Arc is a server management tool that provides a unified proxy for managing multiple static sites and dynamic applications.

## TODO

- [ ] Ensure that `sites.services` will actually run the binary with the various arguments.

## Overview

Arc simplifies local development by providing:

- **Unified Proxy Server**: Single entry point for all your local projects
- **Automatic Process Management**: Start, stop, and monitor multiple services
- **File Watching**: Automatic reloading when configuration changes
- **Cloudflare Tunnel Integration**: Expose local services via Cloudflare tunnels
- **Health Monitoring**: Track the status of all your services

## Production Example

For a real-world production example of Arc in use, see the [server](https://github.com/mac9sb/server) repository, which demonstrates a complete setup with multiple static sites and dynamic applications.

## Getting Started

### Installation

Build Arc from source:

```sh
git clone https://github.com/mac9sb/arc.git
cd arc
swift build -c release
```

Or download a pre-built binary from the [releases page](https://github.com/mac9sb/arc/releases).

### Initialize a Project

Create a new Arc project in your current directory:

```sh
arc init
```

This creates the necessary directory structure and example files.

> [!NOTE]
> If your applications and static sites are in separate git repositories, it's recommended to add them as submodules using `git submodule add <repository-url> <path>` rather than committing them directly. This keeps your project structure clean and allows you to track specific versions of each component.

### Configure Your Sites

Edit `ArcManifest.swift` to add your static sites and applications. Arc uses a Swift manifest for configuration.

Example configuration:

```swift
import ArcDescription

let config = ArcConfiguration(
    processName: "my-arc",
    sites: .init(
        services: [
            .init(
                name: "api",
                domain: "api.localhost",
                port: 8000,
                process: .init(
                    workingDir: "apps/api",
                    executable: ".build/release/API"
                )
            )
        ],
        pages: [
            .init(
                name: "portfolio",
                domain: "portfolio.localhost",
                outputPath: "static/portfolio/.output"
            )
        ]
    )
)
```

### Start the Server

Run Arc in foreground mode:

```sh
arc start
```

Or run in background:

```sh
arc start --background
```

The server will start on port 8080 (default) and proxy requests to your configured sites.

## Architecture

Arc consists of several modules:

- **ArcCLI**: Command-line interface and argument parsing
- **ArcCore**: Core configuration and process management
- **ArcServer**: HTTP server and proxy functionality

## Commands

- `arc init` - Initialize a new Arc project
- `arc start` - Start the Arc server
- `arc stop` - Stop running Arc servers
- `arc status` - Check the status of running servers
- `arc logs` - View server logs

## Configuration

Arc uses a Swift manifest named `ArcManifest.swift`. The manifest constructs an `ArcConfiguration` and is evaluated at runtime.

## Development

To contribute to Arc:

1. Clone the repository
2. Build the project: `swift build`
3. Run tests: `swift test`
4. Build documentation: `swift package generate-documentation`

## License

See LICENSE file for details.
