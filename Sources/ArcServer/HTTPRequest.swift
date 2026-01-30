import Foundation

/// Represents an HTTP request received by the server.
///
/// Contains the parsed components of an HTTP request including method, path,
/// headers, and body data.
public struct HTTPRequest: Sendable {
    /// The HTTP method (e.g., "GET", "POST", "PUT", "DELETE").
    public let method: String

    /// The request path, including query string if present.
    public let path: String

    /// HTTP headers as a case-insensitive dictionary.
    ///
    /// Header keys are stored in their original case but can be accessed
    /// case-insensitively.
    public let headers: [String: String]

    /// Request body data.
    ///
    /// Empty `Data` for requests without a body (e.g., GET requests).
    public let body: Data

    /// The Host header value, if present.
    ///
    /// Extracted from the headers dictionary for convenience. Used for
    /// routing requests to the correct site based on domain.
    var host: String? {
        headers.first { $0.key.lowercased() == "host" }?.value
    }
}
