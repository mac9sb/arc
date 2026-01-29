import ArgumentParser
import Foundation
import Noora

public struct InitializeCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new arc project"
    )

    @Argument(help: "Project name (optional, defaults to current directory name)")
    var projectName: String?

    @Option(name: .shortAndLong, help: "Directory to initialize project in")
    var directory: String?

    public func run() throws {
        let targetDir: String
        if let directory = directory {
            targetDir = (directory as NSString).expandingTildeInPath
        } else {
            targetDir = FileManager.default.currentDirectoryPath
        }

        let name = projectName ?? (targetDir as NSString).lastPathComponent
        let sanitizedName = sanitizeProjectName(name)

        Noora().info("Initializing arc project: \(sanitizedName)")
        Noora().info("Target directory: \(targetDir)")

        // Check if directory already exists and has content
        if FileManager.default.fileExists(atPath: targetDir) {
            let contents = try? FileManager.default.contentsOfDirectory(atPath: targetDir)
            if let contents = contents, !contents.isEmpty {
                Noora().error("Directory is not empty: \(targetDir)")
                throw InitError.directoryNotEmpty
            }
        }

        // Create directory structure
        try createDirectoryStructure(in: targetDir, projectName: sanitizedName)
        Noora().success(
            .alert(
                "Project initialized successfully!",
                takeaways: [
                    "cd \(targetDir)",
                    "Build the example API: cd apps/example-api && swift build -c release",
                    "Build the static site: cd static/example-site && swift run ExampleSite",
                    "Start arc: arc start",
                ]))
    }

    // MARK: - Directory Structure

    private func createDirectoryStructure(in baseDir: String, projectName: String) throws {
        let fileManager = FileManager.default

        // Create base directories
        let appsDir = (baseDir as NSString).appendingPathComponent("apps")
        let exampleApiDir = (appsDir as NSString).appendingPathComponent("example-api")
        let exampleApiSourcesDir = (exampleApiDir as NSString).appendingPathComponent(
            "Sources/ExampleAPI")
        let exampleApiControllersDir = (exampleApiSourcesDir as NSString).appendingPathComponent(
            "Controllers")
        let exampleApiPublicDir = (exampleApiDir as NSString).appendingPathComponent("Public")

        let staticDir = (baseDir as NSString).appendingPathComponent("static")
        let exampleSiteDir = (staticDir as NSString).appendingPathComponent("example-site")
        let exampleSiteSourcesDir = (exampleSiteDir as NSString).appendingPathComponent(
            "Sources/ExampleSite")
        let exampleSitePagesDir = (exampleSiteSourcesDir as NSString).appendingPathComponent(
            "Pages")

        // Create directories
        try fileManager.createDirectory(
            atPath: exampleApiControllersDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            atPath: exampleApiPublicDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            atPath: exampleSitePagesDir, withIntermediateDirectories: true)

        // Get resource bundle path
        let resourcesPath = getResourcesPath()

        // Generate files from templates
        try generateExampleAPI(in: exampleApiDir, resourcesPath: resourcesPath)
        try generateExampleSite(in: exampleSiteDir, resourcesPath: resourcesPath)
        try generateArcManifest(in: baseDir, resourcesPath: resourcesPath)
        try generateREADME(in: baseDir, projectName: projectName, resourcesPath: resourcesPath)
    }

    // MARK: - Example API Generation

    private func generateExampleAPI(in dir: String, resourcesPath: String) throws {
        let templates = [
            ("example-api-Package.swift.template", "Package.swift"),
            ("example-api-main.swift.template", "Sources/ExampleAPI/main.swift"),
            ("example-api-Application.swift.template", "Sources/ExampleAPI/Application.swift"),
            (
                "example-api-WebController.swift.template",
                "Sources/ExampleAPI/Controllers/WebController.swift"
            ),
            (
                "example-api-APIController.swift.template",
                "Sources/ExampleAPI/Controllers/APIController.swift"
            ),
            ("example-api-ExamplePage.swift.template", "Sources/ExampleAPI/ExamplePage.swift"),
            ("example-api-HTMLResponse.swift.template", "Sources/ExampleAPI/HTMLResponse.swift"),
        ]

        for (template, destination) in templates {
            let templatePath = (resourcesPath as NSString).appendingPathComponent(template)
            let templateContent = try String(contentsOfFile: templatePath, encoding: .utf8)
            let destPath = (dir as NSString).appendingPathComponent(destination)
            let destDir = (destPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: destDir, withIntermediateDirectories: true)
            try templateContent.write(toFile: destPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Example Site Generation

    private func generateExampleSite(in dir: String, resourcesPath: String) throws {
        let templates = [
            ("example-site-Package.swift.template", "Package.swift"),
            ("example-site-Application.swift.template", "Sources/ExampleSite/Application.swift"),
            ("example-site-Home.swift.template", "Sources/ExampleSite/Pages/Home.swift"),
        ]

        for (template, destination) in templates {
            let templatePath = (resourcesPath as NSString).appendingPathComponent(template)
            let templateContent = try String(contentsOfFile: templatePath, encoding: .utf8)
            let destPath = (dir as NSString).appendingPathComponent(destination)
            let destDir = (destPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: destDir, withIntermediateDirectories: true)
            try templateContent.write(toFile: destPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Config Generation

    private func generateArcManifest(in baseDir: String, resourcesPath: String) throws {
        let templatePath = (resourcesPath as NSString).appendingPathComponent("ArcManifest.swift.template")
        let templateContent = try String(contentsOfFile: templatePath, encoding: .utf8)
        let destPath = (baseDir as NSString).appendingPathComponent("ArcManifest.swift")
        try templateContent.write(toFile: destPath, atomically: true, encoding: .utf8)
    }

    // MARK: - README Generation

    private func generateREADME(in baseDir: String, projectName: String, resourcesPath: String)
        throws
    {
        let templatePath = (resourcesPath as NSString).appendingPathComponent("README.md.template")
        var templateContent = try String(contentsOfFile: templatePath, encoding: .utf8)
        templateContent = templateContent.replacingOccurrences(
            of: "{{PROJECT_NAME}}", with: projectName)
        let destPath = (baseDir as NSString).appendingPathComponent("README.md")
        try templateContent.write(toFile: destPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func sanitizeProjectName(_ name: String) -> String {
        let sanitized =
            name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return sanitized.isEmpty ? "arc-project" : sanitized
    }

    private func getResourcesPath() -> String {
        // Try to use Bundle.module for resources (works when built as package)
        if let resourcesPath = Bundle.module.resourcePath {
            return resourcesPath
        }

        // Fallback: try to find Resources directory relative to the executable
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let executableURL = URL(fileURLWithPath: executablePath)
        var resourcesURL = executableURL.deletingLastPathComponent().appendingPathComponent(
            "Resources")

        // If not found, try relative to Sources/ArcCLI (for development)
        if !FileManager.default.fileExists(atPath: resourcesURL.path) {
            let currentFile = #file
            let currentFileURL = URL(fileURLWithPath: currentFile)
            resourcesURL =
                currentFileURL
                .deletingLastPathComponent()  // Commands
                .deletingLastPathComponent()  // ArcCLI
                .appendingPathComponent("Resources")
        }

        return resourcesURL.path
    }
}

// MARK: - Errors

enum InitError: Error {
    case directoryNotEmpty
    case templateNotFound
    case fileWriteFailed
}

extension InitError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .directoryNotEmpty:
            return
                "Directory is not empty. Please use an empty directory or specify a different location."
        case .templateNotFound:
            return "Template file not found. Please ensure all template files are present."
        case .fileWriteFailed:
            return "Failed to write file. Please check permissions."
        }
    }
}
