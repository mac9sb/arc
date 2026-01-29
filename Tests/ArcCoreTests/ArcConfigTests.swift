import Foundation

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

    @Test("ArcConfig loads manifest")
    func testArcConfigLoadsManifest() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let manifestContents = """
            import ArcDescription

            let config = ArcConfiguration(
                proxyPort: 8080,
                sites: .init(services: [], pages: [])
            )
            """
        let manifestURL = tempDir.appendingPathComponent("ArcManifest.swift")
        try manifestContents.write(to: manifestURL, atomically: true, encoding: .utf8)

        let config = try await ArcConfig.loadFrom(path: manifestURL.path)

        #expect(config.proxyPort == 8080)
        #expect(config.sites.isEmpty)
    }
}
