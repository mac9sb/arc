import ArcCore
import ArgumentParser
import Foundation
import Noora
import PklSwift

/// Thread-safe box for passing errors from async Tasks
private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

/// Command to diagnose common issues with Arc setup and configuration.
///
/// Performs a series of health checks including:
/// - Swift toolchain availability and version
/// - Required dependencies (pkl, cloudflared)
/// - Configuration file validity
/// - Port availability
/// - File permissions
///
/// ## Usage
///
/// ```sh
/// arc doctor              # Run all diagnostics
/// arc doctor --fix        # Attempt to fix issues automatically
/// ```
public struct DoctorCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose common issues with Arc setup"
    )

    /// Path to the Pkl configuration file.
    @Option(name: .shortAndLong, help: "Path to config file")
    var config: String = "config.pkl"

    /// Enable verbose output with additional details.
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    public func run() throws {
        let configPath = config
        let isVerbose = verbose

        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()

        Task { @Sendable in
            defer { semaphore.signal() }
            do {
                try await Self.runDiagnostics(configPath: configPath, verbose: isVerbose)
            } catch {
                errorBox.error = error
            }
        }

        semaphore.wait()
        if let error = errorBox.error {
            throw error
        }
    }

    // MARK: - Diagnostics

    private static func runDiagnostics(configPath: String, verbose: Bool) async throws {
        let noora = Noora()
        var issues: [Issue] = []
        var warnings: [Issue] = []

        noora.info("Arc Doctor - Diagnosing your setup...")
        print("")

        // Check Swift
        print("Checking Swift toolchain...")
        let swiftCheck = await checkSwift(verbose: verbose)
        printCheckResult(swiftCheck)
        if case .error(let msg) = swiftCheck.status {
            issues.append(Issue(category: "Swift", message: msg))
        } else if case .warning(let msg) = swiftCheck.status {
            warnings.append(Issue(category: "Swift", message: msg))
        }

        // Check Pkl
        print("Checking Pkl CLI...")
        let pklCheck = await checkPkl(verbose: verbose)
        printCheckResult(pklCheck)
        if case .error(let msg) = pklCheck.status {
            issues.append(Issue(category: "Pkl", message: msg))
        } else if case .warning(let msg) = pklCheck.status {
            warnings.append(Issue(category: "Pkl", message: msg))
        }

        // Check config file
        print("Checking configuration...")
        let configCheck = await checkConfig(configPath: configPath, verbose: verbose)
        printCheckResult(configCheck)
        if case .error(let msg) = configCheck.status {
            issues.append(Issue(category: "Config", message: msg))
        } else if case .warning(let msg) = configCheck.status {
            warnings.append(Issue(category: "Config", message: msg))
        }

        // Check cloudflared (optional)
        print("Checking cloudflared (optional)...")
        let cloudflaredCheck = await checkCloudflared(verbose: verbose)
        printCheckResult(cloudflaredCheck)
        if case .warning(let msg) = cloudflaredCheck.status {
            warnings.append(Issue(category: "Cloudflared", message: msg))
        }

        // Check ports
        print("Checking port availability...")
        let portCheck = await checkPorts(configPath: configPath, verbose: verbose)
        printCheckResult(portCheck)
        if case .error(let msg) = portCheck.status {
            issues.append(Issue(category: "Ports", message: msg))
        } else if case .warning(let msg) = portCheck.status {
            warnings.append(Issue(category: "Ports", message: msg))
        }

        // Check git submodules
        print("Checking git submodules...")
        let submoduleCheck = await checkSubmodules(verbose: verbose)
        printCheckResult(submoduleCheck)
        if case .error(let msg) = submoduleCheck.status {
            issues.append(Issue(category: "Submodules", message: msg))
        } else if case .warning(let msg) = submoduleCheck.status {
            warnings.append(Issue(category: "Submodules", message: msg))
        }

        // Check log directory
        print("Checking log directory...")
        let logDirCheck = await checkLogDirectory(configPath: configPath, verbose: verbose)
        printCheckResult(logDirCheck)
        if case .error(let msg) = logDirCheck.status {
            issues.append(Issue(category: "Logs", message: msg))
        } else if case .warning(let msg) = logDirCheck.status {
            warnings.append(Issue(category: "Logs", message: msg))
        }

        // Summary
        print("")
        print("─────────────────────────────────────")

        if issues.isEmpty && warnings.isEmpty {
            noora.success("All checks passed! Your Arc setup looks healthy.")
        } else {
            if !issues.isEmpty {
                noora.error("\(issues.count) issue(s) found:")
                for issue in issues {
                    print("  • [\(issue.category)] \(issue.message)")
                }
            }
            if !warnings.isEmpty {
                noora.warning("\(warnings.count) warning(s):")
                for warning in warnings {
                    print("  • [\(warning.category)] \(warning.message)")
                }
            }
            print("")
            print("Run 'arc doctor --verbose' for more details.")
        }
    }

    // MARK: - Individual Checks

    private static func checkSwift(verbose: Bool) async -> CheckResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["swift", "--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\n").first ?? "unknown"
                return CheckResult(
                    name: "Swift",
                    status: .ok,
                    details: verbose ? version : nil
                )
            } else {
                return CheckResult(
                    name: "Swift",
                    status: .error("Swift not found. Install Xcode or Swift toolchain."),
                    details: nil
                )
            }
        } catch {
            return CheckResult(
                name: "Swift",
                status: .error("Failed to check Swift: \(error.localizedDescription)"),
                details: nil
            )
        }
    }

    private static func checkPkl(verbose: Bool) async -> CheckResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["pkl", "--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return CheckResult(
                    name: "Pkl",
                    status: .ok,
                    details: verbose ? version : nil
                )
            } else {
                return CheckResult(
                    name: "Pkl",
                    status: .warning("Pkl not found. Install from https://pkl-lang.org for config validation."),
                    details: nil
                )
            }
        } catch {
            return CheckResult(
                name: "Pkl",
                status: .warning("Pkl not found. Install from https://pkl-lang.org for config validation."),
                details: nil
            )
        }
    }

    private static func checkConfig(configPath: String, verbose: Bool) async -> CheckResult {
        let expandedPath = (configPath as NSString).expandingTildeInPath
        let resolvedPath: String
        if (expandedPath as NSString).isAbsolutePath {
            resolvedPath = expandedPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return CheckResult(
                name: "Config",
                status: .error("Config file not found: \(resolvedPath)"),
                details: verbose ? "Create config.pkl or specify path with --config" : nil
            )
        }

        // Try to load and validate config
        let configURL = URL(fileURLWithPath: resolvedPath)
        do {
            let config = try await ArcConfig.loadFrom(
                source: ModuleSource.path(resolvedPath),
                configPath: configURL
            )
            
            var details: [String] = []
            if verbose {
                details.append("Proxy port: \(config.proxyPort)")
                details.append("Sites: \(config.sites.count)")
                for site in config.sites {
                    details.append("  - \(site.name) (\(site.domain))")
                }
            }
            
            return CheckResult(
                name: "Config",
                status: .ok,
                details: verbose ? details.joined(separator: "\n") : nil
            )
        } catch {
            return CheckResult(
                name: "Config",
                status: .error("Config validation failed: \(error.localizedDescription)"),
                details: verbose ? "Run 'pkl eval \(configPath)' for details" : nil
            )
        }
    }

    private static func checkCloudflared(verbose: Bool) async -> CheckResult {
        let commonPaths = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "/usr/bin/cloudflared"
        ]

        // Check PATH first
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["cloudflared"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return CheckResult(
                    name: "Cloudflared",
                    status: .ok,
                    details: verbose ? "Found at: \(path)" : nil
                )
            }
        } catch {
            // Continue to check common paths
        }

        // Check common paths
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return CheckResult(
                    name: "Cloudflared",
                    status: .ok,
                    details: verbose ? "Found at: \(path)" : nil
                )
            }
        }

        return CheckResult(
            name: "Cloudflared",
            status: .warning("Not found (optional - needed for Cloudflare Tunnels)"),
            details: verbose ? "Install with: brew install cloudflared" : nil
        )
    }

    private static func checkPorts(configPath: String, verbose: Bool) async -> CheckResult {
        let expandedPath = (configPath as NSString).expandingTildeInPath
        let resolvedPath: String
        if (expandedPath as NSString).isAbsolutePath {
            resolvedPath = expandedPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return CheckResult(
                name: "Ports",
                status: .warning("Cannot check ports without valid config"),
                details: nil
            )
        }

        let configURL = URL(fileURLWithPath: resolvedPath)
        do {
            let config = try await ArcConfig.loadFrom(
                source: ModuleSource.path(resolvedPath),
                configPath: configURL
            )

            var portsToCheck: [(Int, String)] = [(config.proxyPort, "proxy")]

            for site in config.sites {
                if case .app(let appSite) = site {
                    portsToCheck.append((appSite.port, site.name))
                }
            }

            var inUse: [(Int, String)] = []
            for (port, name) in portsToCheck {
                if isPortInUse(port) {
                    inUse.append((port, name))
                }
            }

            if inUse.isEmpty {
                return CheckResult(
                    name: "Ports",
                    status: .ok,
                    details: verbose ? "All configured ports are available" : nil
                )
            } else {
                let portList = inUse.map { "\($0.0) (\($0.1))" }.joined(separator: ", ")
                return CheckResult(
                    name: "Ports",
                    status: .warning("Ports in use: \(portList)"),
                    details: verbose ? "This may be expected if Arc is already running" : nil
                )
            }
        } catch {
            return CheckResult(
                name: "Ports",
                status: .warning("Cannot check ports: config load failed"),
                details: nil
            )
        }
    }

    private static func isPortInUse(_ port: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-i", ":\(port)", "-P", "-n"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    private static func checkSubmodules(verbose: Bool) async -> CheckResult {
        let currentDir = FileManager.default.currentDirectoryPath

        // Check if .gitmodules exists
        let gitmodulesPath = (currentDir as NSString).appendingPathComponent(".gitmodules")
        guard FileManager.default.fileExists(atPath: gitmodulesPath) else {
            return CheckResult(
                name: "Submodules",
                status: .ok,
                details: verbose ? "No submodules configured" : nil
            )
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["submodule", "status"]
        task.currentDirectoryURL = URL(fileURLWithPath: currentDir)

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check for uninitialized submodules (lines starting with -)
            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            let uninitialized = lines.filter { $0.hasPrefix("-") }

            if uninitialized.isEmpty {
                return CheckResult(
                    name: "Submodules",
                    status: .ok,
                    details: verbose ? "\(lines.count) submodule(s) initialized" : nil
                )
            } else {
                return CheckResult(
                    name: "Submodules",
                    status: .warning("\(uninitialized.count) submodule(s) not initialized"),
                    details: verbose ? "Run: git submodule update --init --recursive" : nil
                )
            }
        } catch {
            return CheckResult(
                name: "Submodules",
                status: .warning("Could not check submodule status"),
                details: nil
            )
        }
    }

    private static func checkLogDirectory(configPath: String, verbose: Bool) async -> CheckResult {
        let expandedPath = (configPath as NSString).expandingTildeInPath
        let resolvedPath: String
        if (expandedPath as NSString).isAbsolutePath {
            resolvedPath = expandedPath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
        }

        var logDir = "/var/log/arc"  // Default

        // Try to get log dir from config
        if FileManager.default.fileExists(atPath: resolvedPath) {
            let configURL = URL(fileURLWithPath: resolvedPath)
            if let config = try? await ArcConfig.loadFrom(
                source: ModuleSource.path(resolvedPath),
                configPath: configURL
            ) {
                logDir = config.logDir
            }
        }

        let expandedLogDir = (logDir as NSString).expandingTildeInPath

        // Check if directory exists
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expandedLogDir, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                // Check if writable
                if FileManager.default.isWritableFile(atPath: expandedLogDir) {
                    return CheckResult(
                        name: "Log Directory",
                        status: .ok,
                        details: verbose ? "Writable at: \(expandedLogDir)" : nil
                    )
                } else {
                    return CheckResult(
                        name: "Log Directory",
                        status: .warning("Log directory not writable: \(expandedLogDir)"),
                        details: verbose ? "Run: sudo mkdir -p \(expandedLogDir) && sudo chown $USER \(expandedLogDir)" : nil
                    )
                }
            } else {
                return CheckResult(
                    name: "Log Directory",
                    status: .error("Log path exists but is not a directory: \(expandedLogDir)"),
                    details: nil
                )
            }
        } else {
            return CheckResult(
                name: "Log Directory",
                status: .warning("Log directory does not exist: \(expandedLogDir)"),
                details: verbose ? "Will be created on first run, or run: sudo mkdir -p \(expandedLogDir) && sudo chown $USER \(expandedLogDir)" : nil
            )
        }
    }

    // MARK: - Helpers

    private struct CheckResult {
        let name: String
        let status: Status
        let details: String?

        enum Status {
            case ok
            case warning(String)
            case error(String)
        }
    }

    private struct Issue {
        let category: String
        let message: String
    }

    private static func printCheckResult(_ result: CheckResult) {
        switch result.status {
        case .ok:
            print("  ✓ \(result.name)")
        case .warning(let msg):
            print("  ⚠ \(result.name): \(msg)")
        case .error(let msg):
            print("  ✗ \(result.name): \(msg)")
        }

        if let details = result.details {
            for line in details.components(separatedBy: "\n") {
                print("    \(line)")
            }
        }
    }
}
