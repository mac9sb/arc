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
    
    @Test("GenerateConfig includes SSH ingress rule when enabled")
    func testGenerateConfigIncludesSSHWhenEnabled() throws {
        let staticSite = StaticSite(
            name: "test-site",
            domain: "test.localhost",
            outputPath: "static/test/.output"
        )
        
        let sshConfig = SshConfig(
            enabled: true,
            domain: "ssh.example.com",
            port: 22
        )
        
        let config = ArcConfig(
            proxyPort: 8080,
            sites: [.static(staticSite)],
            ssh: sshConfig
        )
        
        let tunnel = CloudflareTunnel(
            enabled: true,
            cloudflaredPath: "/usr/local/bin/cloudflared",
            tunnelName: nil,
            tunnelUUID: "test-uuid-123",
            configPath: "~/.cloudflared/config.yml"
        )
        
        let yaml = try CloudflaredConfigGenerator.generateConfig(config: config, tunnel: tunnel)
        
        #expect(yaml.contains("hostname: ssh.example.com"))
        #expect(yaml.contains("service: ssh://localhost:22"))
    }
    
    @Test("GenerateConfig throws error when SSH enabled but domain missing")
    func testGenerateConfigThrowsErrorWhenSSHEnabledButDomainMissing() throws {
        let staticSite = StaticSite(
            name: "test-site",
            domain: "test.localhost",
            outputPath: "static/test/.output"
        )
        
        let sshConfig = SshConfig(
            enabled: true,
            domain: nil,
            port: 22
        )
        
        let config = ArcConfig(
            proxyPort: 8080,
            sites: [.static(staticSite)],
            ssh: sshConfig
        )
        
        let tunnel = CloudflareTunnel(
            enabled: true,
            cloudflaredPath: "/usr/local/bin/cloudflared",
            tunnelName: nil,
            tunnelUUID: "test-uuid-123",
            configPath: "~/.cloudflared/config.yml"
        )
        
        #expect(throws: CloudflaredConfigError.sshDomainRequired) {
            try CloudflaredConfigGenerator.generateConfig(config: config, tunnel: tunnel)
        }
    }
    
    @Test("GenerateConfig uses custom SSH port when specified")
    func testGenerateConfigUsesCustomSSHPort() throws {
        let staticSite = StaticSite(
            name: "test-site",
            domain: "test.localhost",
            outputPath: "static/test/.output"
        )
        
        let sshConfig = SshConfig(
            enabled: true,
            domain: "ssh.example.com",
            port: 2222
        )
        
        let config = ArcConfig(
            proxyPort: 8080,
            sites: [.static(staticSite)],
            ssh: sshConfig
        )
        
        let tunnel = CloudflareTunnel(
            enabled: true,
            cloudflaredPath: "/usr/local/bin/cloudflared",
            tunnelName: nil,
            tunnelUUID: "test-uuid-123",
            configPath: "~/.cloudflared/config.yml"
        )
        
        let yaml = try CloudflaredConfigGenerator.generateConfig(config: config, tunnel: tunnel)
        
        #expect(yaml.contains("hostname: ssh.example.com"))
        #expect(yaml.contains("service: ssh://localhost:2222"))
    }
    
    @Test("GenerateConfig does not include SSH when disabled")
    func testGenerateConfigDoesNotIncludeSSHWhenDisabled() throws {
        let staticSite = StaticSite(
            name: "test-site",
            domain: "test.localhost",
            outputPath: "static/test/.output"
        )
        
        let sshConfig = SshConfig(
            enabled: false,
            domain: "ssh.example.com",
            port: 22
        )
        
        let config = ArcConfig(
            proxyPort: 8080,
            sites: [.static(staticSite)],
            ssh: sshConfig
        )
        
        let tunnel = CloudflareTunnel(
            enabled: true,
            cloudflaredPath: "/usr/local/bin/cloudflared",
            tunnelName: nil,
            tunnelUUID: "test-uuid-123",
            configPath: "~/.cloudflared/config.yml"
        )
        
        let yaml = try CloudflaredConfigGenerator.generateConfig(config: config, tunnel: tunnel)
        
        #expect(!yaml.contains("hostname: ssh.example.com"))
        #expect(!yaml.contains("service: ssh://localhost:22"))
    }
}
