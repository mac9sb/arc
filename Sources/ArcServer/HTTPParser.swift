import Foundation

/// Parses HTTP request data.
enum HTTPParser {
  static func parse(data: Data) -> HTTPRequest? {
    guard let requestString = String(data: data, encoding: .utf8) else { return nil }
    guard let headerEndRange = requestString.range(of: "\r\n\r\n") else { return nil }

    let headerSection = String(requestString[..<headerEndRange.lowerBound])
    let lines = headerSection.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { return nil }

    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2 else { return nil }

    let method = String(parts[0])
    let path = String(parts[1])

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      let components = line.split(separator: ":", maxSplits: 1)
      guard components.count == 2 else { continue }
      let key = components[0].trimmingCharacters(in: .whitespaces)
      let value = components[1].trimmingCharacters(in: .whitespaces)
      headers[key] = value
    }

    let bodyStartIndex = headerEndRange.upperBound
    let bodyString = requestString[bodyStartIndex...]
    let body = Data(bodyString.utf8)

    return HTTPRequest(method: method, path: path, headers: headers, body: body)
  }
}

