import ArcCore
import Foundation
import UniformTypeIdentifiers

/// Handles serving static site files from disk.
///
/// Serves pre-built static site files from configured output directories,
/// with support for directory listings and proper MIME type detection.
///
/// ## Example
///
/// ```swift
/// let handler = StaticFileHandler(config: arcConfig)
/// let response = handler.handle(request: httpRequest, site: staticSite, baseDir: baseDir)
/// ```
struct StaticFileHandler {
  private let config: ArcConfig

  /// Creates a new static file handler.
  ///
  /// - Parameter config: The Arc configuration containing site definitions.
  init(config: ArcConfig) {
    self.config = config
  }

  func handle(request: HTTPRequest, site: StaticSite, baseDir: String?) -> HTTPResponse {
    let resolvedBase = resolvePath(site.outputPath, baseDir: baseDir)
    let sanitizedPath = sanitize(path: request.path)
    let fullPath = URL(fileURLWithPath: resolvedBase).appendingPathComponent(sanitizedPath).path

    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) {
      if isDir.boolValue {
        // Try index.html first
        let indexPath = (fullPath as NSString).appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: indexPath) {
          return serveFile(at: indexPath)
        }
        return directoryListing(at: fullPath, requestPath: sanitizedPath)
      } else {
        return serveFile(at: fullPath)
      }
    }

    return HTTPResponse(
      status: 404,
      reason: "Not Found",
      headers: ["Content-Type": "text/plain"],
      body: Data("Not Found".utf8)
    )
  }

  private func serveFile(at path: String) -> HTTPResponse {
    guard let data = FileManager.default.contents(atPath: path) else {
      return HTTPResponse(
        status: 500,
        reason: "Server Error",
        headers: ["Content-Type": "text/plain"],
        body: Data("Failed to read file".utf8)
      )
    }

    let mimeType = mimeTypeFor(path: path)
    return HTTPResponse(
      status: 200,
      reason: "OK",
      headers: ["Content-Type": mimeType],
      body: data
    )
  }

  private func directoryListing(at path: String, requestPath: String) -> HTTPResponse {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
      return HTTPResponse(status: 403, reason: "Forbidden", headers: [:], body: Data())
    }

    let listItems = entries.sorted().map { entry -> String in
      let href = requestPath.hasSuffix("/") ? requestPath + entry : requestPath + "/" + entry
      return "<li><a href=\"\(href)\">\(entry)</a></li>"
    }.joined(separator: "\n")

    let html = """
      <html>
        <head><title>Index of /\(requestPath)</title></head>
        <body>
          <h1>Index of /\(requestPath)</h1>
          <ul>\(listItems)</ul>
        </body>
      </html>
      """

    return HTTPResponse(
      status: 200,
      reason: "OK",
      headers: ["Content-Type": "text/html; charset=utf-8"],
      body: Data(html.utf8)
    )
  }

  private func sanitize(path: String) -> String {
    let trimmed = path.split(separator: "?").first.map(String.init) ?? path
    let components = trimmed.split(separator: "/").filter { $0 != ".." }
    let rebuilt = components.joined(separator: "/")
    return rebuilt.isEmpty ? "." : rebuilt
  }

  private func resolvePath(_ path: String, baseDir: String?) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    if (expanded as NSString).isAbsolutePath {
      return expanded
    }
    if let baseDir {
      return (baseDir as NSString).appendingPathComponent(expanded)
    }
    return expanded
  }

  private func mimeTypeFor(path: String) -> String {
    let ext = (path as NSString).pathExtension
    if let type = UTType(filenameExtension: ext)?.preferredMIMEType {
      return type
    }
    return "application/octet-stream"
  }
}

