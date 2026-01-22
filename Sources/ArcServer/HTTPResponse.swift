import Foundation

/// Represents an HTTP response.
struct HTTPResponse {
  /// HTTP status code.
  let statusCode: Int

  /// HTTP reason phrase.
  let reason: String

  /// HTTP headers as a dictionary.
  var headers: [String: String]

  /// Response body data.
  var body: Data

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

