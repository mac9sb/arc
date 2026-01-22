# Arc

Arc is a server management tool that provides a unified proxy for managing multiple static sites and dynamic applications.

## Overview

Arc simplifies local development by providing:

- **Unified Proxy Server**: Single entry point for all your local projects
- **Automatic Process Management**: Start, stop, and monitor multiple services
- **File Watching**: Automatic reloading when configuration changes
- **Cloudflare Tunnel Integration**: Expose local services via Cloudflare tunnels
- **Health Monitoring**: Track the status of all your services

## Getting Started

### Installation

Build Arc from source:

```bash
git clone https://github.com/mac9sb/arc.git
cd arc
swift build -c release
```

Or download a pre-built binary from the [releases page](https://github.com/mac9sb/arc/releases).

### Initialize a Project

Create a new Arc project in your current directory:

```bash
arc init
```

This creates the necessary directory structure and example files.

### Configure Your Sites

Edit `pkl/config.pkl` to add your static sites and applications. Arc uses Pkl (Programmable Configuration Language) for configuration.

See the [Pkl Configuration Documentation](https://mac9sb.github.io/arc/) for the complete configuration schema.

Example configuration:

```pkl
amends "ArcConfiguration.pkl"

sites {
    new {
        kind = "static"
        name = "portfolio"
        domain = "portfolio.localhost"
        outputPath = "static/portfolio/.output"
    }
    new {
        kind = "app"
        name = "api"
        domain = "api.localhost"
        port = 8000
        process {
            workingDir = "apps/api"
            executable = ".build/release/API"
        }
    }
}
```

### Start the Server

Run Arc in foreground mode:

```bash
arc run
```

Or run in background:

```bash
arc run --background
```

The server will start on port 8080 (default) and proxy requests to your configured sites.

## Architecture

Arc consists of several modules:

- **ArcCLI**: Command-line interface and argument parsing
- **ArcCore**: Core configuration and process management
- **ArcServer**: HTTP server and proxy functionality

## Commands

- `arc init` - Initialize a new Arc project
- `arc run` - Start the Arc server
- `arc stop` - Stop running Arc servers
- `arc status` - Check the status of running servers
- `arc logs` - View server logs

## Configuration

Arc uses Pkl for configuration. The configuration schema is defined in `Sources/ArcCLI/Resources/ArcConfiguration.pkl`. See the [Pkl Documentation](https://mac9sb.github.io/arc/) for detailed information about all configuration options.

## Development

To contribute to Arc:

1. Clone the repository
2. Build the project: `swift build`
3. Run tests: `swift test`
4. Build documentation: `swift package generate-documentation`

## License

See LICENSE file for details.
