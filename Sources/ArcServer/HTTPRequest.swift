import Foundation

/// Represents an HTTP request.
struct HTTPRequest {
  /// The HTTP method (e.g., "GET", "POST").
  let method: String

  /// The request path.
  let path: String

  /// HTTP headers as a dictionary.
  let headers: [String: String]

  /// Request body data.
  let body: Data

  /// The Host header value, if present.
  var host: String? {
    headers.first { $0.key.lowercased() == "host" }?.value
  }
}

