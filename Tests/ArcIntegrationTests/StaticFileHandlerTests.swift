import Foundation
import Testing

@testable import ArcCore
@testable import ArcServer

/// Integration tests for StaticFileHandler.
///
/// Tests static file serving including MIME type detection, directory listings,
/// index.html fallback, and path sanitization.
@Suite("StaticFileHandler Tests")
struct StaticFileHandlerTests {
    
    // MARK: - Test Setup
    
    /// Creates a temporary directory with test files for static file serving tests.
    func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arc-test-\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create test files
        let indexHTML = "<html><body>Hello World</body></html>"
        try indexHTML.write(to: tempDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        
        let styleCSS = "body { color: red; }"
        try styleCSS.write(to: tempDir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        
        let scriptJS = "console.log('test');"
        try scriptJS.write(to: tempDir.appendingPathComponent("script.js"), atomically: true, encoding: .utf8)
        
        // Create subdirectory with files
        let subdir = tempDir.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic bytes
        try imageData.write(to: subdir.appendingPathComponent("logo.png"))
        
        return tempDir
    }
    
    /// Cleans up the temporary test directory.
    func cleanupTestDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Creates a test configuration with a single static site.
    func createTestConfig(outputPath: String) -> ArcConfig {
        ArcConfig(
            proxyPort: 8080,
            sites: [
                .static(StaticSite(
                    name: "test-site",
                    domain: "test.localhost",
                    outputPath: outputPath
                ))
            ]
        )
    }
    
    // MARK: - File Serving Tests
    
    @Test("Serves index.html for root path")
    func testServesIndexForRoot() throws {
        let testDir = try createTestDirectory()
        defer { cleanupTestDirectory(testDir) }
        
        let config = createTestConfig(outputPath: testDir.path)
        let handler = StaticFileHandler(config: config)
        let staticSite = StaticSite(name: "test", domain: "test.localhost", outputPath: testDir.path)
        
        let request = HTTPRequest(
            method: "GET",
            path: "/",
            headers: ["Host": "test.localhost"],
            body: Data()
        )
        
        let response = handler.handle(request: request, site: staticSite, baseDir: nil)
        
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"]?.contains("text/html") == true)
        let body = String(data: response.body, encoding: .utf8)
        #expect(body?.contains("Hello World") == true)
    }
    
    @Test("Serves CSS files with correct MIME type")
    func testServesCSSWithCorrectMIME() throws {
        let testDir = try createTestDirectory()
        defer { cleanupTestDirectory(testDir) }
        
        let config = createTestConfig(outputPath: testDir.path)
        let handler = StaticFileHandler(config: config)
        let staticSite = StaticSite(name: "test", domain: "test.localhost", outputPath: testDir.path)
        
        let request = HTTPRequest(
            method: "GET",
            path: "/style.css",
            headers: ["Host": "test.localhost"],
            body: Data()
        )
        
        let response = handler.handle(request: request, site: staticSite, baseDir: nil)
        
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "text/css")
        let body = String(data: response.body, encoding: .utf8)
        #expect(body?.contains("color: red") == true)
    }
    
    @Test("Serves JavaScript files with correct MIME type")
    func testServesJSWithCorrectMIME() throws {
        let testDir = try createTestDirectory()
        defer { cleanupTestDirectory(testDir) }
        
        let config = createTestConfig(outputPath: testDir.path)
        let handler = StaticFileHandler(config: config)
        let staticSite = StaticSite(name: "test", domain: "test.localhost", outputPath: testDir.path)
        
        let request = HTTPRequest(
            method: "GET",
            path: "/script.js",
            headers: ["Host": "test.localhost"],
            body: Data()
        )
        
        let response = handler.handle(request: request, site: staticSite, baseDir: nil)
        
        #expect(response.statusCode == 200)
        // MIME type can be "application/javascript" or "text/javascript" depending on system
        let contentType = response.headers["Content-Type"] ?? ""
        #expect(contentType.contains("javascript"))
    }
    
    @Test("Returns 404 for non-existent files")
    func testReturns404ForMissingFiles() throws {
        let testDir = try createTestDirectory()
        defer { cleanupTestDirectory(testDir) }
        
        let config = createTestConfig(outputPath: testDir.path)
        let handler = StaticFileHandler(config: config)
        let staticSite = StaticSite(name: "test", domain: "test.localhost", outputPath: testDir.path)
        
        let request = HTTPRequest(
            method: "GET",
            path: "/nonexistent.html",
            headers: ["Host": "test.localhost"],
            body: Data()
        )
        
        let response = handler.handle(request: request, site: staticSite, baseDir: nil)
        
        #expect(response.statusCode == 404)
    }
    
    @Test("Serves files from subdirectories")
    func testServesSubdirectoryFiles() throws {
        let testDir = try createTestDirectory()
        defer { cleanupTestDirectory(testDir) }
        
        let config = createTestConfig(outputPath: testDir.path)
        let handler = StaticFileHandler(config: config)
        let staticSite = StaticSite(name: "test", domain: "test.localhost", outputPath: testDir.path)
        
        let request = HTTPRequest(
            method: "GET",
            path: "/assets/logo.png",
            headers: ["Host": "test.localhost"],
            body: Data()
        )
        
        let response = handler.handle(request: request, site: staticSite, baseDir: nil)
        
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "image/png")
    }
    
    // MARK: - Path Sanitization Tests
    
    @Test("Sanitizes path traversal attempts")
    func testSanitizesPathTraversal() throws {
        let testDir = try createTestDirectory()
        defer { cleanupTestDirectory(testDir) }
        
        let config = createTestConfig(outputPath: testDir.path)
        let handler = StaticFileHandler(config: config)
        let staticSite = StaticSite(name: "test", domain: "test.localhost", outputPath: testDir.path)
        
        // Attempt to traverse outside the output directory
        let request = HTTPRequest(
            method: "GET",
            path: "/../../../etc/passwd",
            headers: ["Host": "test.localhost"],
            body: Data()
        )
        
        let response = handler.handle(request: request, site: staticSite, baseDir: nil)
        
        // Should either return 404 or the sanitized path result, not the actual file
        #expect(response.statusCode == 404 || !String(data: response.body, encoding: .utf8)!.contains("root:"))
    }
    
    @Test("Handles query strings in paths")
    func testHandlesQueryStrings() throws {
        let testDir = try createTestDirectory()
        defer { cleanupTestDirectory(testDir) }
        
        let config = createTestConfig(outputPath: testDir.path)
        let handler = StaticFileHandler(config: config)
        let staticSite = StaticSite(name: "test", domain: "test.localhost", outputPath: testDir.path)
        
        let request = HTTPRequest(
            method: "GET",
            path: "/style.css?v=123",
            headers: ["Host": "test.localhost"],
            body: Data()
        )
        
        let response = handler.handle(request: request, site: staticSite, baseDir: nil)
        
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "text/css")
    }
    
    // MARK: - Directory Listing Tests
    
    @Test("Shows directory listing when no index.html")
    func testDirectoryListing() throws {
        let testDir = try createTestDirectory()
        defer { cleanupTestDirectory(testDir) }
        
        let config = createTestConfig(outputPath: testDir.path)
        let handler = StaticFileHandler(config: config)
        let staticSite = StaticSite(name: "test", domain: "test.localhost", outputPath: testDir.path)
        
        // Request the assets subdirectory which has no index.html
        let request = HTTPRequest(
            method: "GET",
            path: "/assets",
            headers: ["Host": "test.localhost"],
            body: Data()
        )
        
        let response = handler.handle(request: request, site: staticSite, baseDir: nil)
        
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"]?.contains("text/html") == true)
        let body = String(data: response.body, encoding: .utf8)
        #expect(body?.contains("logo.png") == true)
    }
}
