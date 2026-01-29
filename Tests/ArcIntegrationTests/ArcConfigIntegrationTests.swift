import Foundation
import Testing

@testable import ArcCore

/// Integration tests for ArcConfig.
///
/// Tests configuration parsing, site matching, domain routing logic,
/// and config validation.
@Suite("ArcConfig Integration Tests")
struct ArcConfigIntegrationTests {

    // MARK: - Site Configuration Tests

    @Test("Static site has required properties")
    func testStaticSiteProperties() {
        let site = StaticSite(
            name: "portfolio",
            domain: "example.com",
            outputPath: "static/portfolio/.output"
        )

        #expect(site.name == "portfolio")
        #expect(site.domain == "example.com")
        #expect(site.outputPath == "static/portfolio/.output")
        #expect(site.watchTargets == nil)
    }

    @Test("App site has required properties")
    func testAppSiteProperties() {
        let site = AppSite(
            name: "api",
            domain: "api.example.com",
            port: 8001,
            healthPath: "/health",
            process: ProcessConfig(
                workingDir: "apps/api",
                executable: ".build/release/API"
            )
        )

        #expect(site.name == "api")
        #expect(site.domain == "api.example.com")
        #expect(site.port == 8001)
        #expect(site.healthPath == "/health")
        #expect(site.process.workingDir == "apps/api")
        #expect(site.process.executable == ".build/release/API")
    }

    @Test("AppSite generates correct health URL")
    func testAppSiteHealthURL() {
        let site = AppSite(
            name: "api",
            domain: "api.example.com",
            port: 8001,
            healthPath: "/health",
            process: ProcessConfig(workingDir: "apps/api")
        )

        let healthURL = site.healthURL()

        #expect(healthURL != nil)
        #expect(healthURL?.absoluteString == "http://127.0.0.1:8001/health")
    }

    @Test("AppSite generates correct base URL")
    func testAppSiteBaseURL() {
        let site = AppSite(
            name: "api",
            domain: "api.example.com",
            port: 8001,
            process: ProcessConfig(workingDir: "apps/api")
        )

        let baseURL = site.baseURL()

        #expect(baseURL != nil)
        #expect(baseURL?.absoluteString == "http://127.0.0.1:8001")
    }

    // MARK: - Config Construction Tests

    @Test("ArcConfig can be constructed with defaults")
    func testConfigWithDefaults() {
        let config = ArcConfig()

        #expect(config.proxyPort == 8080)
        #expect(config.healthCheckInterval == 30)
        #expect(config.version == "V.2.0.0")
        #expect(config.sites.isEmpty)
        #expect(config.cloudflare == nil)
        #expect(config.ssh == nil)
    }

    @Test("ArcConfig can be constructed with custom values")
    func testConfigWithCustomValues() {
        let config = ArcConfig(
            proxyPort: 9090,
            logDir: "/var/log/myapp",
            baseDir: "/opt/myapp",
            healthCheckInterval: 60,
            version: "1.0.0",
            region: "us-west-1",
            sites: [
                .static(StaticSite(name: "site1", domain: "site1.com", outputPath: ".output")),
                .app(
                    AppSite(
                        name: "app1",
                        domain: "app1.com",
                        port: 8001,
                        process: ProcessConfig(workingDir: "apps/app1")
                    )),
            ],
            processName: "my-arc-server"
        )

        #expect(config.proxyPort == 9090)
        #expect(config.logDir == "/var/log/myapp")
        #expect(config.baseDir == "/opt/myapp")
        #expect(config.healthCheckInterval == 60)
        #expect(config.version == "1.0.0")
        #expect(config.region == "us-west-1")
        #expect(config.sites.count == 2)
        #expect(config.processName == "my-arc-server")
    }

    // MARK: - Site Enum Tests

    @Test("Site enum correctly identifies static sites")
    func testSiteEnumStatic() {
        let staticSite = StaticSite(name: "portfolio", domain: "example.com", outputPath: ".output")
        let site = Site.static(staticSite)

        #expect(site.name == "portfolio")
        #expect(site.domain == "example.com")
        #expect(site.id == "portfolio")

        if case .static(let s) = site {
            #expect(s.outputPath == ".output")
        } else {
            Issue.record("Expected static site")
        }
    }

    @Test("Site enum correctly identifies app sites")
    func testSiteEnumApp() {
        let appSite = AppSite(
            name: "api",
            domain: "api.example.com",
            port: 8001,
            process: ProcessConfig(workingDir: "apps/api")
        )
        let site = Site.app(appSite)

        #expect(site.name == "api")
        #expect(site.domain == "api.example.com")
        #expect(site.id == "api")

        if case .app(let s) = site {
            #expect(s.port == 8001)
        } else {
            Issue.record("Expected app site")
        }
    }

    // MARK: - Domain Matching Tests

    @Test("Can find site by exact domain match")
    func testExactDomainMatch() {
        let config = ArcConfig(
            sites: [
                .static(StaticSite(name: "site1", domain: "site1.localhost", outputPath: ".output")),
                .static(StaticSite(name: "site2", domain: "site2.localhost", outputPath: ".output")),
                .app(AppSite(name: "api", domain: "api.localhost", port: 8001, process: ProcessConfig(workingDir: "apps/api"))),
            ]
        )

        let matchedSite = config.sites.first { $0.domain == "api.localhost" }

        #expect(matchedSite != nil)
        #expect(matchedSite?.name == "api")
    }

    @Test("Domain matching is case-insensitive")
    func testCaseInsensitiveDomainMatch() {
        let config = ArcConfig(
            sites: [
                .static(StaticSite(name: "site1", domain: "Example.COM", outputPath: ".output"))
            ]
        )

        let matchedSite = config.sites.first { $0.domain.lowercased() == "example.com" }

        #expect(matchedSite != nil)
        #expect(matchedSite?.name == "site1")
    }

    @Test("Returns nil for unmatched domain")
    func testUnmatchedDomain() {
        let config = ArcConfig(
            sites: [
                .static(StaticSite(name: "site1", domain: "site1.localhost", outputPath: ".output"))
            ]
        )

        let matchedSite = config.sites.first { $0.domain == "unknown.localhost" }

        #expect(matchedSite == nil)
    }

    // MARK: - Watch Config Tests

    @Test("WatchConfig has correct defaults")
    func testWatchConfigDefaults() {
        let watchConfig = WatchConfig()

        #expect(watchConfig.watchConfig == true)
        #expect(watchConfig.followSymlinks == false)
        #expect(watchConfig.debounceMs == 300)
        #expect(watchConfig.cooldownMs == 1000)
    }

    @Test("WatchConfig can be customized")
    func testWatchConfigCustom() {
        let watchConfig = WatchConfig(
            watchConfig: false,
            followSymlinks: true,
            debounceMs: 500,
            cooldownMs: 2000
        )

        #expect(watchConfig.watchConfig == false)
        #expect(watchConfig.followSymlinks == true)
        #expect(watchConfig.debounceMs == 500)
        #expect(watchConfig.cooldownMs == 2000)
    }

    // MARK: - Cloudflare Config Tests

    @Test("CloudflareTunnel has correct defaults")
    func testCloudflareTunnelDefaults() {
        let tunnel = CloudflareTunnel()

        #expect(tunnel.enabled == false)
        #expect(tunnel.cloudflaredPath == "/opt/homebrew/bin/cloudflared")
        #expect(tunnel.tunnelName == nil)
        #expect(tunnel.tunnelUUID == nil)
    }

    @Test("CloudflareTunnel can be fully configured")
    func testCloudflareTunnelCustom() {
        let tunnel = CloudflareTunnel(
            enabled: true,
            cloudflaredPath: "/usr/local/bin/cloudflared",
            tunnelName: "my-tunnel",
            tunnelUUID: "abc-123-def"
        )

        #expect(tunnel.enabled == true)
        #expect(tunnel.cloudflaredPath == "/usr/local/bin/cloudflared")
        #expect(tunnel.tunnelName == "my-tunnel")
        #expect(tunnel.tunnelUUID == "abc-123-def")
    }

    // MARK: - SSH Config Tests

    @Test("SshConfig has correct defaults")
    func testSshConfigDefaults() {
        let sshConfig = SshConfig()

        #expect(sshConfig.enabled == false)
        #expect(sshConfig.domain == nil)
        #expect(sshConfig.port == 22)
    }

    @Test("SshConfig can be fully configured")
    func testSshConfigCustom() {
        let sshConfig = SshConfig(
            enabled: true,
            domain: "ssh.example.com",
            port: 2222
        )

        #expect(sshConfig.enabled == true)
        #expect(sshConfig.domain == "ssh.example.com")
        #expect(sshConfig.port == 2222)
    }

    // MARK: - ProcessConfig Tests

    @Test("ProcessConfig with executable")
    func testProcessConfigExecutable() {
        let processConfig = ProcessConfig(
            workingDir: "apps/myapp",
            executable: ".build/release/MyApp"
        )

        #expect(processConfig.workingDir == "apps/myapp")
        #expect(processConfig.executable == ".build/release/MyApp")
        #expect(processConfig.command == nil)
    }

    @Test("ProcessConfig with command and args")
    func testProcessConfigCommand() {
        let processConfig = ProcessConfig(
            workingDir: "apps/myapp",
            command: "swift",
            args: ["run", "--release"]
        )

        #expect(processConfig.workingDir == "apps/myapp")
        #expect(processConfig.command == "swift")
        #expect(processConfig.args == ["run", "--release"])
    }

    @Test("ProcessConfig with environment variables")
    func testProcessConfigEnv() {
        let processConfig = ProcessConfig(
            workingDir: "apps/myapp",
            executable: ".build/release/MyApp",
            env: [
                "DATABASE_URL": "postgres://localhost/db",
                "LOG_LEVEL": "debug",
            ]
        )

        #expect(processConfig.env?["DATABASE_URL"] == "postgres://localhost/db")
        #expect(processConfig.env?["LOG_LEVEL"] == "debug")
    }

    // MARK: - Hashable/Equatable Tests

    @Test("ArcConfig is Hashable")
    func testConfigHashable() {
        let config1 = ArcConfig(proxyPort: 8080)
        let config2 = ArcConfig(proxyPort: 8080)
        let config3 = ArcConfig(proxyPort: 9090)

        #expect(config1 == config2)
        #expect(config1 != config3)
        #expect(config1.hashValue == config2.hashValue)
    }

    @Test("Site is Hashable")
    func testSiteHashable() {
        let site1 = Site.static(StaticSite(name: "test", domain: "test.com", outputPath: ".output"))
        let site2 = Site.static(StaticSite(name: "test", domain: "test.com", outputPath: ".output"))
        let site3 = Site.static(StaticSite(name: "other", domain: "other.com", outputPath: ".output"))

        #expect(site1 == site2)
        #expect(site1 != site3)
    }
}
