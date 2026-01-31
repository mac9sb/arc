import ArcDescription
import Foundation

public enum ArcManifestLoader {
    /// Loads an `ArcConfiguration` from a Swift manifest file and converts it to `ArcConfig`.
    ///
    /// - Parameter path: Path to `Arc.swift` or a directory containing it.
    /// - Returns: Loaded `ArcConfig` with `baseDir` inferred if missing.
    /// - Throws: `ArcError` when the manifest path cannot be resolved or the manifest fails to compile or run.
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
    // Compile manifest to temporary executable
    let tempDir = FileManager.default.temporaryDirectory
    let executableURL = tempDir.appendingPathComponent("arc-manifest-runner-\(UUID().uuidString)")

    let compileTask = Process()
    compileTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")

    var compileArgs: [String] = ["swiftc"]

    for path in moduleSearchPaths {
        compileArgs.append(contentsOf: ["-I", path])
    }

    for path in librarySearchPaths {
        compileArgs.append(contentsOf: ["-L", path])
    }

    compileArgs.append(contentsOf: [
        "-lArcDescription",
        manifestPath,
        runnerPath,
        "-o", executableURL.path,
    ])
    compileTask.arguments = compileArgs

    let errorPipe = Pipe()
    compileTask.standardError = errorPipe

    try compileTask.run()
    compileTask.waitUntilExit()

    if compileTask.terminationStatus != 0 {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

        // Clean up
        try? FileManager.default.removeItem(at: executableURL)

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

    // Execute the compiled binary
    let runTask = Process()
    runTask.executableURL = executableURL

    let outputPipe = Pipe()
    let runErrorPipe = Pipe()
    runTask.standardOutput = outputPipe
    runTask.standardError = runErrorPipe

    try runTask.run()
    runTask.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

    // Clean up executable
    try? FileManager.default.removeItem(at: executableURL)

    if runTask.terminationStatus != 0 {
        let errorData = runErrorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
        throw ArcError.configLoadFailed("Manifest execution failed: \(errorMessage)")
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

            Create an Arc.swift file in your project root.
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
        let manifestPath = (resolvedPath as NSString).appendingPathComponent("Arc.swift")
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            throw ArcError.invalidConfiguration(
                """
                Arc.swift not found in directory: \(resolvedPath)

                Create Arc.swift in this directory.
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

    func checkCandidate(_ path: String) -> Bool {
        containsArcDescriptionModule(at: path) || containsArcDescriptionLibrary(at: path)
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

    for candidate in runtimeCandidates {
        if checkCandidate(candidate) {
            let modulePath = (candidate as NSString).appendingPathComponent("Modules")
            return ([modulePath], [candidate])
        }
    }

    // Development candidates - search common locations
    let currentDir = fileManager.currentDirectoryPath
    let currentDirURL = URL(fileURLWithPath: currentDir)

    // Check current directory and parent directories for tooling/arc
    var searchURL = currentDirURL
    for _ in 0..<5 {  // Search up to 5 levels up
        let toolingArcBuild = searchURL.appendingPathComponent("tooling/arc/.build")

        // Prefer release over debug to avoid mixing build configurations
        let preferredPaths = [
            toolingArcBuild.appendingPathComponent("release").path,
            toolingArcBuild.appendingPathComponent("arm64-apple-macosx/release").path,
            toolingArcBuild.appendingPathComponent("debug").path,
            toolingArcBuild.appendingPathComponent("arm64-apple-macosx/debug").path,
        ]

        // Return the first valid path found (don't mix multiple build dirs)
        for path in preferredPaths {
            if fileManager.fileExists(atPath: path) && checkCandidate(path) {
                let modulePath = (path as NSString).appendingPathComponent("Modules")
                return ([modulePath], [path])
            }
        }

        searchURL = searchURL.deletingLastPathComponent()
    }

    return ([], [])
}

private func containsArcDescriptionModule(at path: String) -> Bool {
    let moduleCandidates = [
        "ArcDescription.swiftmodule",
        "ArcDescription.swiftmodule/arm64-apple-macosx.swiftmodule",
        "ArcDescription.swiftmodule/x86_64-apple-macosx.swiftmodule",
        "Modules/ArcDescription.swiftmodule",
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
