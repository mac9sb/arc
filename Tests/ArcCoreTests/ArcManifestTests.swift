import Foundation
import Testing
@testable import ArcCore
@testable import ArcDescription

@Suite("ArcManifest Loading and Validation Tests")
struct ArcManifestTests {

    // MARK: - Valid Configuration Tests

    @Test("Load minimal valid manifest")
    func loadMinimalManifest() throws {
        let manifestContent = """
        import ArcDescription

        let config = ArcConfiguration()
        """

        let config = try loadManifestFromString(manifestContent)
        #expect(config.proxyPort == 8080)
        #expect(config.sites.services.isEmpty)
        #expect(config.sites.pages.isEmpty)
    }

    @Test("Load manifest with static site")
    func loadStaticSiteManifest() throws {
        let manifestContent = """
        import ArcDescription

        let config = ArcConfiguration(
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
        """

        let config = try loadManifestFromString(manifestContent)
        #expect(config.sites.pages.count == 1)
        #expect(config.sites.pages[0].name == "portfolio")
        #expect(config.sites.pages[0].domain == "example.com")
        #expect(config.sites.pages[0].outputPath == "static/portfolio/.output")
    }

    @Test("Load manifest with service")
    func loadServiceManifest() throws {
        let manifestContent = """
        import ArcDescription

        let config = ArcConfiguration(
            sites: .init(
                services: [
                    .init(
                        name: "api",
                        domain: "api.example.com",
                        port: 8000,
                        process: .init(
                            workingDir: "apps/api/",
                            executable: ".build/release/API"
                        )
                    )
                ],
                pages: []
            )
        )
        """

        let config = try loadManifestFromString(manifestContent)
        #expect(config.sites.services.count == 1)
        #expect(config.sites.services[0].name == "api")
        #expect(config.sites.services[0].port == 8000)
        #expect(config.sites.services[0].process.executable == ".build/release/API")
    }

    @Test("Load manifest with multiple services and pages")
    func loadComplexManifest() throws {
        let manifestContent = """
        import ArcDescription

        let config = ArcConfiguration(
            processName: "test-server",
            sites: .init(
                services: [
                    .init(
                        name: "api",
                        domain: "api.example.com",
                        port: 8000,
                        process: .init(workingDir: "apps/api/", executable: ".build/release/API")
                    ),
                    .init(
                        name: "admin",
                        domain: "admin.example.com",
                        port: 8001,
                        process: .init(workingDir: "apps/admin/", executable: ".build/release/Admin")
                    )
                ],
                pages: [
                    .init(name: "marketing", domain: "example.com", outputPath: "static/marketing/.output"),
                    .init(name: "docs", domain: "docs.example.com", outputPath: "static/docs/.output")
                ]
            )
        )
        """

        let config = try loadManifestFromString(manifestContent)
        #expect(config.processName == "test-server")
        #expect(config.sites.services.count == 2)
        #expect(config.sites.pages.count == 2)
    }

    @Test("Load manifest with Cloudflare configuration")
    func loadCloudflareManifest() throws {
        let manifestContent = """
        import ArcDescription

        let config = ArcConfiguration(
            extensions: [
                .cloudflare(.cloudflare(
                    tunnelName: "test-tunnel",
                    tunnelUUID: "12345678-1234-1234-1234-123456789abc"
                ))
            ]
        )
        """

        let config = try loadManifestFromString(manifestContent)
        #expect(config.cloudflare != nil)
        #expect(config.cloudflare?.tunnelName == "test-tunnel")
        #expect(config.cloudflare?.tunnelUUID == "12345678-1234-1234-1234-123456789abc")
    }

    @Test("Load manifest with SSH configuration")
    func loadSSHManifest() throws {
        let manifestContent = """
        import ArcDescription

        let config = ArcConfiguration(
            extensions: [
                .ssh(.ssh(
                    domain: "ssh.example.com",
                    port: 22
                ))
            ]
        )
        """

        let config = try loadManifestFromString(manifestContent)
        #expect(config.ssh != nil)
        #expect(config.ssh?.domain == "ssh.example.com")
        #expect(config.ssh?.port == 22)
    }

    // MARK: - Validation Tests

    @Test("Reject duplicate service ports")
    func rejectDuplicatePorts() {
        #expect(throws: Error.self) {
            _ = ArcConfiguration(
                sites: .init(
                    services: [
                        .init(name: "api1", domain: "api1.local", port: 8000, process: .init(workingDir: ".", executable: "test")),
                        .init(name: "api2", domain: "api2.local", port: 8000, process: .init(workingDir: ".", executable: "test"))
                    ]
                )
            )
        }
    }

    @Test("Reject duplicate site names")
    func rejectDuplicateNames() {
        #expect(throws: Error.self) {
            _ = ArcConfiguration(
                sites: .init(
                    services: [
                        .init(name: "test", domain: "test1.local", port: 8000, process: .init(workingDir: ".", executable: "test"))
                    ],
                    pages: [
                        .init(name: "test", domain: "test2.local", outputPath: "static/.output")
                    ]
                )
            )
        }
    }

    @Test("Reject invalid service port (too low)")
    func rejectLowPort() {
        #expect(throws: Error.self) {
            _ = ServiceSite(
                name: "test",
                domain: "test.local",
                port: 1024,  // Must be > 1024
                process: .init(workingDir: ".", executable: "test")
            )
        }
    }

    @Test("Reject invalid service port (too high)")
    func rejectHighPort() {
        #expect(throws: Error.self) {
            _ = ServiceSite(
                name: "test",
                domain: "test.local",
                port: 65536,  // Must be < 65536
                process: .init(workingDir: ".", executable: "test")
            )
        }
    }

    @Test("Reject empty service name")
    func rejectEmptyServiceName() {
        #expect(throws: Error.self) {
            _ = ServiceSite(
                name: "",
                domain: "test.local",
                port: 8000,
                process: .init(workingDir: ".", executable: "test")
            )
        }
    }

    @Test("Reject service name with whitespace")
    func rejectServiceNameWithWhitespace() {
        #expect(throws: Error.self) {
            _ = ServiceSite(
                name: "test service",
                domain: "test.local",
                port: 8000,
                process: .init(workingDir: ".", executable: "test")
            )
        }
    }

    @Test("Reject empty domain")
    func rejectEmptyDomain() {
        #expect(throws: Error.self) {
            _ = ServiceSite(
                name: "test",
                domain: "",
                port: 8000,
                process: .init(workingDir: ".", executable: "test")
            )
        }
    }

    @Test("Reject empty static site name")
    func rejectEmptyStaticSiteName() {
        #expect(throws: Error.self) {
            _ = StaticSite(
                name: "",
                domain: "test.local",
                outputPath: "static/.output"
            )
        }
    }

    @Test("Reject empty output path")
    func rejectEmptyOutputPath() {
        #expect(throws: Error.self) {
            _ = StaticSite(
                name: "test",
                domain: "test.local",
                outputPath: ""
            )
        }
    }

    @Test("Reject health path without leading slash")
    func rejectInvalidHealthPath() {
        #expect(throws: Error.self) {
            _ = ServiceSite(
                name: "test",
                domain: "test.local",
                port: 8000,
                healthPath: "health",  // Must start with /
                process: .init(workingDir: ".", executable: "test")
            )
        }
    }

    @Test("Reject empty working directory")
    func rejectEmptyWorkingDir() {
        #expect(throws: Error.self) {
            _ = ProcessConfig(workingDir: "")
        }
    }

    @Test("Reject process config without executable or command")
    func rejectMissingExecutableAndCommand() {
        #expect(throws: Error.self) {
            _ = ProcessConfig(
                workingDir: ".",
                executable: nil,
                command: nil
            )
        }
    }

    @Test("Reject empty executable")
    func rejectEmptyExecutable() {
        #expect(throws: Error.self) {
            _ = ProcessConfig(
                workingDir: ".",
                executable: ""
            )
        }
    }

    @Test("Reject empty command")
    func rejectEmptyCommand() {
        #expect(throws: Error.self) {
            _ = ProcessConfig(
                workingDir: ".",
                command: ""
            )
        }
    }

    @Test("Reject invalid proxy port")
    func rejectInvalidProxyPort() {
        #expect(throws: Error.self) {
            _ = ArcConfiguration(proxyPort: 0)
        }

        #expect(throws: Error.self) {
            _ = ArcConfiguration(proxyPort: 65536)
        }
    }

    @Test("Reject negative health check interval")
    func rejectNegativeHealthCheckInterval() {
        #expect(throws: Error.self) {
            _ = ArcConfiguration(healthCheckInterval: 0)
        }
    }

    @Test("Reject empty log directory")
    func rejectEmptyLogDir() {
        #expect(throws: Error.self) {
            _ = ArcConfiguration(logDir: "")
        }
    }

    @Test("Reject Cloudflare enabled without tunnel name or UUID")
    func rejectCloudflareWithoutTunnel() {
        #expect(throws: Error.self) {
            _ = CloudflareConfig(
                tunnelName: nil,
                tunnelUUID: nil
            )
        }
    }

    @Test("Reject SSH enabled without domain")
    func rejectSSHWithoutDomain() {
        #expect(throws: Error.self) {
            _ = SshConfig(
                domain: ""
            )
        }
    }

    @Test("Reject negative debounce interval")
    func rejectNegativeDebounce() {
        #expect(throws: Error.self) {
            _ = WatchConfig(debounceMs: -1)
        }
    }

    // MARK: - Edge Cases

    @Test("Accept valid port at boundaries")
    func acceptValidPortBoundaries() throws {
        // Port 1025 should work (just above minimum)
        let service1 = ServiceSite(
            name: "test1",
            domain: "test.local",
            port: 1025,
            process: .init(workingDir: ".", executable: "test")
        )
        #expect(service1.port == 1025)

        // Port 65535 should work (maximum)
        let service2 = ServiceSite(
            name: "test2",
            domain: "test.local",
            port: 65535,
            process: .init(workingDir: ".", executable: "test")
        )
        #expect(service2.port == 65535)
    }

    @Test("Accept ProcessConfig with executable only")
    func acceptExecutableOnly() throws {
        let process = ProcessConfig(
            workingDir: ".",
            executable: "test"
        )
        #expect(process.executable == "test")
        #expect(process.command == nil)
    }

    @Test("Accept ProcessConfig with command only")
    func acceptCommandOnly() throws {
        let process = ProcessConfig(
            workingDir: ".",
            command: "swift run"
        )
        #expect(process.command == "swift run")
        #expect(process.executable == nil)
    }

    @Test("Accept Cloudflare with tunnel name only")
    func acceptCloudflareWithNameOnly() throws {
        let cf = CloudflareConfig(
            tunnelName: "test-tunnel"
        )
        #expect(cf.tunnelName == "test-tunnel")
        #expect(cf.tunnelUUID == nil)
    }

    @Test("Accept Cloudflare with UUID only")
    func acceptCloudflareWithUUIDOnly() throws {
        let cf = CloudflareConfig(
            tunnelUUID: "12345678-1234-1234-1234-123456789abc"
        )
        #expect(cf.tunnelUUID == "12345678-1234-1234-1234-123456789abc")
        #expect(cf.tunnelName == nil)
    }

    @Test("Accept multiple unique services and pages")
    func acceptMultipleUniqueSites() throws {
        let config = ArcConfiguration(
            sites: .init(
                services: [
                    .init(name: "api", domain: "api.local", port: 8000, process: .init(workingDir: ".", executable: "test")),
                    .init(name: "admin", domain: "admin.local", port: 8001, process: .init(workingDir: ".", executable: "test")),
                    .init(name: "worker", domain: "worker.local", port: 8002, process: .init(workingDir: ".", executable: "test"))
                ],
                pages: [
                    .init(name: "site1", domain: "site1.local", outputPath: "static1/.output"),
                    .init(name: "site2", domain: "site2.local", outputPath: "static2/.output")
                ]
            )
        )

        #expect(config.sites.services.count == 3)
        #expect(config.sites.pages.count == 2)
    }

    // MARK: - Helper Methods

    private func loadManifestFromString(_ content: String) throws -> ArcConfiguration {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arc-manifest-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let manifestPath = tempDir.appendingPathComponent("ArcManifest.swift")
        try content.write(to: manifestPath, atomically: true, encoding: .utf8)

        let arcConfig = try ArcManifestLoader.load(from: manifestPath.path)
        return arcConfig.configuration
    }
}

// MARK: - Integration Tests

@Suite("ArcManifest Integration Tests")
struct ArcManifestIntegrationTests {

    @Test("Load manifest from directory")
    func loadFromDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arc-manifest-dir-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let manifestContent = """
        import ArcDescription

        let config = ArcConfiguration(
            processName: "directory-test"
        )
        """

        let manifestPath = tempDir.appendingPathComponent("ArcManifest.swift")
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)

        // Load from directory path (not file path)
        let arcConfig = try ArcManifestLoader.load(from: tempDir.path)
        #expect(arcConfig.configuration.processName == "directory-test")
    }

    @Test("BaseDir inference from manifest location")
    func baseDirInference() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arc-basedir-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let manifestContent = """
        import ArcDescription

        let config = ArcConfiguration()
        """

        let manifestPath = tempDir.appendingPathComponent("ArcManifest.swift")
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)

        let arcConfig = try ArcManifestLoader.load(from: manifestPath.path)
        #expect(arcConfig.configuration.baseDir == tempDir.path)
    }

    @Test("Error for missing manifest file")
    func errorForMissingFile() throws {
        let nonExistentPath = "/tmp/nonexistent-manifest-\(UUID().uuidString).swift"

        #expect(throws: Error.self) {
            _ = try ArcManifestLoader.load(from: nonExistentPath)
        }
    }

    @Test("Error for directory without ArcManifest.swift")
    func errorForDirectoryWithoutManifest() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arc-no-manifest-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        #expect(throws: Error.self) {
            _ = try ArcManifestLoader.load(from: tempDir.path)
        }
    }
}
