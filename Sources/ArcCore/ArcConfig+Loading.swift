import Foundation

/// Lightweight module source wrapper for loading Swift manifests.
/// This preserves call-site compatibility.
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

    /// Legacy signature that ignores `configPath`.
    public static func loadFrom(path: String, configPath: URL?) throws -> ArcConfig {
        try ArcManifestLoader.load(from: path)
    }

    /// Legacy async signature that ignores `configPath`.
    public static func loadFrom(path: String, configPath: URL?) async throws -> ArcConfig {
        try ArcManifestLoader.load(from: path)
    }

    /// Legacy signature for module source loading with optional config path.
    public static func loadFrom(source: ModuleSource) async throws -> ArcConfig {
        try ArcManifestLoader.load(from: source.path)
    }

    /// Legacy signature for module source loading.
    public static func loadFrom(source: ModuleSource, configPath: URL? = nil) async throws -> ArcConfig {
        try ArcManifestLoader.load(from: source.path)
    }
}
