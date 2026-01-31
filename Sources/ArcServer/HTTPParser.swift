import Foundation

/// Parser for HTTP request data.
///
/// Parses raw HTTP request bytes into a structured `HTTPRequest` object,
/// extracting method, path, headers, and body.
enum HTTPParser {
    /// Errors that can occur during HTTP request parsing.
    enum ParseError: Error, LocalizedError {
        case invalidEncoding
        case malformedRequest(reason: String)
        case invalidRequestLine(line: String)
        case missingHeaders

        var errorDescription: String? {
            switch self {
            case .invalidEncoding:
                return "Request data is not valid UTF-8"
            case .malformedRequest(let reason):
                return "Malformed HTTP request: \(reason)"
            case .invalidRequestLine(let line):
                return "Invalid HTTP request line: '\(line)'"
            case .missingHeaders:
                return "HTTP request missing required headers section"
            }
        }
    }

    /// Parses raw HTTP request data into an `HTTPRequest`.
    ///
    /// Parses the HTTP request line, headers, and body from raw bytes.
    /// Expects HTTP/1.1 format with `\r\n` line endings.
    ///
    /// - Parameter data: The raw HTTP request bytes.
    /// - Returns: A parsed `HTTPRequest`.
    /// - Throws: `ParseError` if parsing fails with diagnostic information.
    static func parse(data: Data) throws -> HTTPRequest {
        guard let requestString = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }

        guard let headerEndRange = requestString.range(of: "\r\n\r\n") else {
            throw ParseError.missingHeaders
        }

        let headerSection = String(requestString[..<headerEndRange.lowerBound])
        let lines = headerSection.components(separatedBy: "\r\n")

        guard let requestLine = lines.first else {
            throw ParseError.malformedRequest(reason: "Empty request")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            throw ParseError.invalidRequestLine(line: requestLine)
        }

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
