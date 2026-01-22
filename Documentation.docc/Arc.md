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

See the ``GettingStarted`` tutorial to set up your first Arc project.

## Configuration

Arc uses Pkl (Programmable Configuration Language) for configuration. See the ``Configuration`` tutorial for details on setting up your `config.pkl` file.

For complete Pkl configuration schema documentation, see the [Pkl Configuration Documentation](/arc/pkldoc/).

## Commands

- ``init`` - Initialize a new Arc project
- ``run`` - Start the Arc server
- ``stop`` - Stop running Arc servers
- ``status`` - Check the status of running servers
- ``logs`` - View server logs

## Architecture

Arc consists of several modules:

- **ArcCLI**: Command-line interface and argument parsing
- **ArcCore**: Core configuration and process management
- **ArcServer**: HTTP server and proxy functionality
