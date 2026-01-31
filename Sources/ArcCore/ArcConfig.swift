// Arc configuration model for Swift manifests.

import Foundation
import ArcDescription

// MARK: - ArcConfig

/// Arc configuration for local development, backed by `ArcDescription`.
///
/// This type wraps `ArcConfiguration` and provides a more ergonomic Swift API.
/// Simple properties are forwarded via `@dynamicMemberLookup`, while complex
/// properties like `sites`, `cloudflare`, and `ssh` provide custom transformation logic.
@dynamicMemberLookup
public struct ArcConfig: Hashable, Sendable {
    public var configuration: ArcConfiguration

    /// Unified list of sites (static pages and services).
    public var sites: [Site] {
        get {
            configuration.sites.pages.map(Site.static)
                + configuration.sites.services.map(Site.app)
        }
        set {
            let pages = newValue.compactMap { site -> StaticSite? in
                if case .static(let value) = site { return value }
                return nil
            }
            let services = newValue.compactMap { site -> AppSite? in
                if case .app(let value) = site { return value }
                return nil
            }
            configuration.sites = Sites(services: services, pages: pages)
        }
    }

    public var cloudflare: CloudflareTunnel? {
        get { configuration.cloudflare }
        set { configuration.cloudflare = newValue }
    }

    public var ssh: SshConfig? {
        get { configuration.ssh }
        set { configuration.ssh = newValue }
    }

    /// Forwards read/write access to simple properties on the underlying configuration.
    ///
    /// This subscript allows direct access to properties like `proxyPort`, `logDir`,
    /// `baseDir`, `healthCheckInterval`, `version`, `region`, `processName`, and `watch`
    /// without needing explicit pass-through computed properties.
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<ArcConfiguration, T>) -> T {
        get { configuration[keyPath: keyPath] }
        set { configuration[keyPath: keyPath] = newValue }
    }

    public init(
        proxyPort: Int = 8080,
        logDir: String = "~/Library/Logs/arc",
        baseDir: String? = nil,
        healthCheckInterval: Int = 30,
        version: String = "V.2.0.0",
        region: String? = nil,
        sites: [Site] = [],
        cloudflare: CloudflareTunnel? = nil,
        ssh: SshConfig? = nil,
        watch: WatchConfig = WatchConfig(),
        processName: String? = nil
    ) {
        let pages = sites.compactMap { site -> StaticSite? in
            if case .static(let value) = site { return value }
            return nil
        }
        let services = sites.compactMap { site -> AppSite? in
            if case .app(let value) = site { return value }
            return nil
        }

        self.configuration = ArcConfiguration(
            proxyPort: proxyPort,
            logDir: logDir,
            baseDir: baseDir,
            healthCheckInterval: healthCheckInterval,
            version: version,
            region: region,
            processName: processName,
            sites: Sites(services: services, pages: pages),
            watch: watch,
            extensions: Extensions(cloudflare: cloudflare, ssh: ssh)
        )
    }

    public init(configuration: ArcConfiguration) {
        self.configuration = configuration
    }
}

// MARK: - Site (Discriminated Union)

/// Unified site configuration with discriminator.
public enum Site: Hashable, Sendable, Identifiable {
    case `static`(StaticSite)
    case app(AppSite)

    public var id: String {
        switch self {
        case .static(let site): return site.name
        case .app(let site): return site.name
        }
    }

    public var name: String {
        switch self {
        case .static(let site): return site.name
        case .app(let site): return site.name
        }
    }

    public var domain: String {
        switch self {
        case .static(let site): return site.domain
        case .app(let site): return site.domain
        }
    }

    public var watchTargets: [String]? {
        switch self {
        case .static(let site): return site.watchTargets
        case .app(let site): return site.watchTargets
        }
    }
}

// MARK: - Typealiases

public typealias StaticSite = ArcDescription.StaticSite
public typealias AppSite = ArcDescription.ServiceSite
public typealias ProcessConfig = ArcDescription.ProcessConfig
public typealias WatchConfig = ArcDescription.WatchConfig
public typealias CloudflareTunnel = ArcDescription.CloudflareConfig
public typealias SshConfig = ArcDescription.SshConfig
public typealias Sites = ArcDescription.Sites

// MARK: - Service Helpers

extension AppSite {
    /// Returns the full URL for health checks.
    public func healthURL() -> URL? {
        URL(string: "http://127.0.0.1:\(port)\(healthPath)")
    }

    /// Returns the base URL for the application.
    public func baseURL() -> URL? {
        URL(string: "http://127.0.0.1:\(port)")
    }
}
