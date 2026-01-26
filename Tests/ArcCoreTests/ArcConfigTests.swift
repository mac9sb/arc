import Foundation
import PklSwift
import Testing

@testable import ArcCore

@Suite("ArcConfig Tests")
struct ArcConfigTests {
    @Test("ArcConfig initializes with defaults")
    func testArcConfigDefaults() {
        let config = ArcConfig()

        #expect(config.proxyPort == 8080)
        #expect(config.logDir == "~/Library/Logs/arc")
        #expect(config.healthCheckInterval == 30)
        #expect(config.version == "V.2.0.0")
        #expect(config.sites.isEmpty)
    }

    @Test("ArcConfig initializes with custom values")
    func testArcConfigCustom() {
        let staticSite = StaticSite(
            name: "test",
            domain: "test.localhost",
            outputPath: "static/test/.output"
        )

        let config = ArcConfig(
            proxyPort: 9000,
            logDir: "/tmp/logs",
            healthCheckInterval: 60,
            sites: [.static(staticSite)]
        )

        #expect(config.proxyPort == 9000)
        #expect(config.logDir == "/tmp/logs")
        #expect(config.healthCheckInterval == 60)
        #expect(config.sites.count == 1)
    }

    @Test("Site enum cases work correctly")
    func testSiteEnum() {
        let staticSite = StaticSite(
            name: "static",
            domain: "static.localhost",
            outputPath: "static/.output"
        )

        let appSite = AppSite(
            name: "app",
            domain: "app.localhost",
            port: 8000,
            process: ProcessConfig(workingDir: "apps/app")
        )

        let staticSiteEnum = Site.static(staticSite)
        let appSiteEnum = Site.app(appSite)

        #expect(staticSiteEnum.name == "static")
        #expect(staticSiteEnum.domain == "static.localhost")
        #expect(appSiteEnum.name == "app")
        #expect(appSiteEnum.domain == "app.localhost")
    }

    @Test("ArcConfig loads schema from modulepath")
    func testArcConfigLoadsSchemaFromModulepath() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ArcCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // arc
            .appendingPathComponent("Sources/ArcCLI/Resources/ArcConfiguration.pkl")
        let arcConfigContents = try String(contentsOf: resourceURL, encoding: .utf8)
        let arcConfigURL = tempDir.appendingPathComponent("ArcConfiguration.pkl")
        try arcConfigContents.write(to: arcConfigURL, atomically: true, encoding: .utf8)

        let configContents = """
        amends "modulepath:/ArcConfiguration.pkl"

        sites {}
        """
        let configURL = tempDir.appendingPathComponent("config.pkl")
        try configContents.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try await ArcConfig.loadFrom(
            source: ModuleSource.path(configURL.path),
            configPath: configURL
        )

        #expect(config.sites.isEmpty)
    }
}
