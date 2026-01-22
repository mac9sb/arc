import Foundation
import Testing

@testable import ArcCore

@Suite("CloudflaredConfigGenerator Tests")
struct CloudflaredConfigGeneratorTests {
    @Test("GenerateConfig requires tunnel UUID")
    func testGenerateConfigRequiresTunnelUUID() async throws {
        let config = ArcConfig(
            proxyPort: 8080,
            sites: []
        )
        
        let tunnel = CloudflareTunnel(
            enabled: true,
            cloudflaredPath: "/usr/local/bin/cloudflared",
            tunnelName: nil,
            tunnelUUID: nil,
            configPath: "~/.cloudflared/config.yml"
        )
        
        #expect(throws: CloudflaredConfigError.tunnelUUIDRequired) {
            try CloudflaredConfigGenerator.generateConfig(config: config, tunnel: tunnel)
        }
    }
    
    @Test("GenerateConfig requires sites with domains")
    func testGenerateConfigRequiresSites() async throws {
        let config = ArcConfig(
            proxyPort: 8080,
            sites: []
        )
        
        let tunnel = CloudflareTunnel(
            enabled: true,
            cloudflaredPath: "/usr/local/bin/cloudflared",
            tunnelName: nil,
            tunnelUUID: "test-uuid",
            configPath: "~/.cloudflared/config.yml"
        )
        
        #expect(throws: CloudflaredConfigError.noSitesConfigured) {
            try CloudflaredConfigGenerator.generateConfig(config: config, tunnel: tunnel)
        }
    }
    
    @Test("GenerateConfig creates valid YAML")
    func testGenerateConfigCreatesValidYAML() throws {
        let staticSite = StaticSite(
            name: "test-site",
            domain: "test.localhost",
            outputPath: "static/test/.output"
        )
        
        let config = ArcConfig(
            proxyPort: 8080,
            sites: [.static(staticSite)]
        )
        
        let tunnel = CloudflareTunnel(
            enabled: true,
            cloudflaredPath: "/usr/local/bin/cloudflared",
            tunnelName: nil,
            tunnelUUID: "test-uuid-123",
            configPath: "~/.cloudflared/config.yml"
        )
        
        let yaml = try CloudflaredConfigGenerator.generateConfig(config: config, tunnel: tunnel)
        
        #expect(yaml.contains("tunnel: test-uuid-123"))
        #expect(yaml.contains("credentials-file:"))
        #expect(yaml.contains("ingress:"))
        #expect(yaml.contains("hostname: test.localhost"))
        #expect(yaml.contains("service: http://localhost:8080"))
    }
}
