import Foundation
import ArcDescription

public enum ArcManifestLoader {
    /// Loads an `ArcConfiguration` from a Swift manifest file and converts it to `ArcConfig`.
    ///
    /// - Parameter path: Path to `ArcManifest.swift` or a directory containing it.
    /// - Returns: Loaded `ArcConfig` with `baseDir` inferred if missing.
    public static func load(from path: String) throws -> ArcConfig {
        let manifestPath = try resolveManifestPath(path)
        let manifestURL = URL(fileURLWithPath: manifestPath)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arc-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let runnerURL = tempDir.appendingPathComponent("ArcManifestRunner.swift")
        try runnerTemplate.write(to: runnerURL, atomically: true, encoding: .utf8)

        let searchPaths = findArcDescriptionSearchPaths()
        guard !searchPaths.modulePaths.isEmpty, !searchPaths.libraryPaths.isEmpty else {
            throw ArcError.invalidConfiguration(
                """
                ArcDescription module not found.

                To fix this, build Arc first:
                  cd tooling/arc
                  swift build -c release

                The module will be available in .build/release/
                """
            )
        }
        let output = try runSwift(
            manifestPath: manifestPath,
            runnerPath: runnerURL.path,
            moduleSearchPaths: searchPaths.modulePaths,
            librarySearchPaths: searchPaths.libraryPaths
        )

        let decoder = JSONDecoder()
        var configuration = try decoder.decode(ArcConfiguration.self, from: output)

        if configuration.baseDir == nil {
            configuration.baseDir = manifestURL.deletingLastPathComponent().path
        }

        return ArcConfig(configuration: configuration)
    }
}

// MARK: - Runner Template

private let runnerTemplate = """
import Foundation
import ArcDescription

@main
struct ArcManifestRunner {
    static func main() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(config)
        FileHandle.standardOutput.write(data)
    }
}
"""

// MARK: - Process Execution

private func runSwift(
    manifestPath: String,
    runnerPath: String,
    moduleSearchPaths: [String],
    librarySearchPaths: [String]
) throws -> Data {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")

    var arguments: [String] = ["swift"]

    for path in moduleSearchPaths {
        arguments.append(contentsOf: ["-I", path])
    }

    for path in librarySearchPaths {
        arguments.append(contentsOf: ["-L", path])
    }

    arguments.append(contentsOf: ["-lArcDescription", manifestPath, runnerPath])
    task.arguments = arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = errorPipe

    try task.run()
    task.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    if task.terminationStatus != 0 {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

        // Provide helpful error message based on common issues
        var helpfulMessage = "Swift manifest compilation failed.\n\n"

        if errorMessage.contains("import ArcDescription") || errorMessage.contains("No such module 'ArcDescription'") {
            helpfulMessage += """
            Missing import or module not found.

            Make sure your manifest starts with:
              import ArcDescription

            And that Arc is built:
              cd tooling/arc && swift build -c release
            """
        } else if errorMessage.contains("cannot find 'config' in scope") {
            helpfulMessage += """
            Missing 'config' variable.

            Your manifest must define:
              let config = ArcConfiguration(...)

            See Documentation.docc/Examples/ for examples.
            """
        } else if errorMessage.contains("precondition") || errorMessage.contains("failed") {
            helpfulMessage += """
            Validation error in configuration.

            Check that:
              - Port numbers are in range 1025-65535
              - Site names are unique and non-empty
              - All required fields are provided

            Error details:
            \(errorMessage)
            """
        } else {
            helpfulMessage += "Compilation error:\n\(errorMessage)"
        }

        throw ArcError.configLoadFailed(helpfulMessage)
    }

    return outputData
}

// MARK: - Manifest Path Resolution

private func resolveManifestPath(_ inputPath: String) throws -> String {
    let expandedPath = (inputPath as NSString).expandingTildeInPath
    let resolvedPath: String
    if (expandedPath as NSString).isAbsolutePath {
        resolvedPath = expandedPath
    } else {
        let currentDir = FileManager.default.currentDirectoryPath
        resolvedPath = (currentDir as NSString).appendingPathComponent(expandedPath)
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory) else {
        throw ArcError.invalidConfiguration(
            """
            Manifest not found at: \(resolvedPath)

            Create an ArcManifest.swift file in your project root.
            See Documentation.docc/Examples/ for examples, or start with:

            import ArcDescription

            let config = ArcConfiguration(
                sites: .init(
                    services: [],
                    pages: []
                )
            )
            """
        )
    }

    if isDirectory.boolValue {
        let manifestPath = (resolvedPath as NSString).appendingPathComponent("ArcManifest.swift")
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            throw ArcError.invalidConfiguration(
                """
                ArcManifest.swift not found in directory: \(resolvedPath)

                Create ArcManifest.swift in this directory.
                See Documentation.docc/Examples/ for examples.
                """
            )
        }
        return manifestPath
    }

    return resolvedPath
}

// MARK: - Search Paths

private func findArcDescriptionSearchPaths() -> (modulePaths: [String], libraryPaths: [String]) {
    let fileManager = FileManager.default
    var modulePaths: [String] = []
    var libraryPaths: [String] = []
    var seen: Set<String> = []

    func addCandidate(_ path: String) {
        guard !seen.contains(path) else { return }
        if containsArcDescriptionModule(at: path) || containsArcDescriptionLibrary(at: path) {
            modulePaths.append(path)
            libraryPaths.append(path)
            seen.insert(path)
        }
    }

    // Runtime installation candidates (relative to executable).
    let executablePath = ProcessInfo.processInfo.arguments[0]
    let executableURL = URL(fileURLWithPath: executablePath)
    let executableDir = executableURL.deletingLastPathComponent()

    let runtimeCandidates = [
        executableDir.path,
        executableDir.deletingLastPathComponent().appendingPathComponent("lib").path,
        executableDir.deletingLastPathComponent().appendingPathComponent("lib/arc").path,
        executableDir.deletingLastPathComponent().appendingPathComponent("share/arc").path,
        executableDir.deletingLastPathComponent().appendingPathComponent("share/arc/lib").path,
    ]

    runtimeCandidates.forEach(addCandidate)

    // Development candidates (SwiftPM build output).
    let currentFileURL = URL(fileURLWithPath: #filePath)
    let packageRoot = currentFileURL
        .deletingLastPathComponent()   // ArcCore
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // arc
    let buildDir = packageRoot.appendingPathComponent(".build")

    if let enumerator = fileManager.enumerator(at: buildDir, includingPropertiesForKeys: nil) {
        for case let url as URL in enumerator {
            if url.lastPathComponent == "debug" || url.lastPathComponent == "release" {
                addCandidate(url.path)
            }
        }
    }

    return (modulePaths, libraryPaths)
}

private func containsArcDescriptionModule(at path: String) -> Bool {
    let moduleCandidates = [
        "ArcDescription.swiftmodule",
        "ArcDescription.swiftmodule/arm64-apple-macosx.swiftmodule",
        "ArcDescription.swiftmodule/x86_64-apple-macosx.swiftmodule",
    ]

    for candidate in moduleCandidates {
        let url = URL(fileURLWithPath: path).appendingPathComponent(candidate)
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }
    }
    return false
}

private func containsArcDescriptionLibrary(at path: String) -> Bool {
    let libCandidates = [
        "libArcDescription.a",
        "libArcDescription.dylib",
    ]

    for candidate in libCandidates {
        let url = URL(fileURLWithPath: path).appendingPathComponent(candidate)
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }
    }
    return false
}
