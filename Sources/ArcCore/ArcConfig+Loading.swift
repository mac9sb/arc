import Foundation

/// Lightweight stand-in for the previous Pkl module source.
/// This preserves call-site compatibility while routing to Swift manifests.
public struct ModuleSource: Sendable, Hashable {
    public let path: String

    public static func path(_ path: String) -> ModuleSource {
        ModuleSource(path: path)
    }
}

extension ArcConfig {
    /// Loads configuration from a Swift manifest path or directory.
    public static func loadFrom(path: String) throws -> ArcConfig {
        try ArcManifestLoader.load(from: path)
    }

    /// Async wrapper for manifest loading.
    public static func loadFrom(path: String) async throws -> ArcConfig {
        try ArcManifestLoader.load(from: path)
    }

    /// Backwards-compatible signature that ignores `configPath`.
    public static func loadFrom(path: String, configPath: URL?) throws -> ArcConfig {
        try ArcManifestLoader.load(from: path)
    }

    /// Backwards-compatible async signature that ignores `configPath`.
    public static func loadFrom(path: String, configPath: URL?) async throws -> ArcConfig {
        try ArcManifestLoader.load(from: path)
    }

    /// Backwards-compatible signature that replaces Pkl module source loading.
    public static func loadFrom(source: ModuleSource) async throws -> ArcConfig {
        try ArcManifestLoader.load(from: source.path)
    }

    /// Backwards-compatible signature that replaces Pkl module source loading.
    public static func loadFrom(source: ModuleSource, configPath: URL? = nil) async throws -> ArcConfig {
        try ArcManifestLoader.load(from: source.path)
    }
}
