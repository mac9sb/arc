import Foundation
import Testing

@testable import ArcCore

@Suite("ArcConfig Tests")
struct ArcConfigTests {
    @Test("ArcConfig initializes with defaults")
    func testArcConfigDefaults() {
        let config = ArcConfig()
        
        #expect(config.proxyPort == 8080)
        #expect(config.logDir == "/var/log/arc")
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
}
