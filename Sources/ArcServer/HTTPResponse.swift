import Foundation

/// Represents an HTTP response to send to the client.
///
/// Contains all components of an HTTP response including status code, headers,
/// and body. Can be serialized to raw HTTP response data.
struct HTTPResponse {
  /// HTTP status code (e.g., 200, 404, 500).
  let statusCode: Int

  /// HTTP reason phrase (e.g., "OK", "Not Found", "Internal Server Error").
  let reason: String

  /// HTTP headers as a dictionary.
  ///
  /// Headers like "Content-Length" and "Connection" are automatically
  /// added during serialization.
  var headers: [String: String]

  /// Response body data.
  var body: Data

  /// Creates a new HTTP response.
  ///
  /// - Parameters:
  ///   - status: The HTTP status code.
  ///   - reason: The HTTP reason phrase.
  ///   - headers: HTTP headers dictionary.
  ///   - body: Response body data.
  init(status: Int, reason: String, headers: [String: String], body: Data) {
    self.statusCode = status
    self.reason = reason
    self.headers = headers
    self.body = body
  }

  func serialize() -> Data {
    var responseLines = ["HTTP/1.1 \(statusCode) \(reason)"]
    var mergedHeaders = headers
    mergedHeaders["Content-Length"] = "\(body.count)"
    mergedHeaders["Connection"] = "close"

    for (key, value) in mergedHeaders {
      responseLines.append("\(key): \(value)")
    }
    responseLines.append("")

    var data = responseLines.joined(separator: "\r\n").data(using: .utf8) ?? Data()
    data.append("\r\n".data(using: .utf8) ?? Data())
    data.append(body)
    return data
  }
}

