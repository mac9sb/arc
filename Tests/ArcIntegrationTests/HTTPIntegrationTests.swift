import Foundation
import Testing

@testable import ArcServer

/// Integration tests for HTTP request/response handling.
///
/// Tests HTTP parsing, response serialization, and request routing
/// without requiring a running server.
@Suite("HTTP Integration Tests")
struct HTTPIntegrationTests {
    
    // MARK: - HTTPRequest Tests
    
    @Test("HTTPRequest stores all properties correctly")
    func testHTTPRequestProperties() {
        let body = "test body".data(using: .utf8)!
        let request = HTTPRequest(
            method: "POST",
            path: "/api/users",
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer token123"
            ],
            body: body
        )
        
        #expect(request.method == "POST")
        #expect(request.path == "/api/users")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Authorization"] == "Bearer token123")
        #expect(request.body == body)
    }
    
    @Test("HTTPRequest handles empty body")
    func testHTTPRequestEmptyBody() {
        let request = HTTPRequest(
            method: "GET",
            path: "/",
            headers: [:],
            body: Data()
        )
        
        #expect(request.method == "GET")
        #expect(request.body.isEmpty)
    }
    
    // MARK: - HTTPResponse Tests
    
    @Test("HTTPResponse serializes correctly")
    func testHTTPResponseSerialization() {
        let response = HTTPResponse(
            status: 200,
            reason: "OK",
            headers: ["Content-Type": "text/plain"],
            body: "Hello, World!".data(using: .utf8)!
        )
        
        let serialized = response.serialize()
        let serializedString = String(data: serialized, encoding: .utf8)!
        
        #expect(serializedString.contains("HTTP/1.1 200 OK"))
        #expect(serializedString.contains("Content-Type: text/plain"))
        #expect(serializedString.contains("Content-Length: 13"))
        #expect(serializedString.contains("Connection: close"))
        #expect(serializedString.contains("Hello, World!"))
    }
    
    @Test("HTTPResponse handles various status codes")
    func testHTTPResponseStatusCodes() {
        let testCases: [(Int, String)] = [
            (200, "OK"),
            (201, "Created"),
            (204, "No Content"),
            (301, "Moved Permanently"),
            (400, "Bad Request"),
            (401, "Unauthorized"),
            (403, "Forbidden"),
            (404, "Not Found"),
            (500, "Internal Server Error"),
            (502, "Bad Gateway"),
            (503, "Service Unavailable")
        ]
        
        for (code, reason) in testCases {
            let response = HTTPResponse(
                status: code,
                reason: reason,
                headers: [:],
                body: Data()
            )
            
            let serialized = String(data: response.serialize(), encoding: .utf8)!
            #expect(serialized.contains("HTTP/1.1 \(code) \(reason)"))
        }
    }
    
    @Test("HTTPResponse calculates content length automatically")
    func testHTTPResponseContentLength() {
        let bodies = [
            "",
            "short",
            String(repeating: "a", count: 1000),
            "unicode: 你好世界"
        ]
        
        for bodyString in bodies {
            let body = bodyString.data(using: .utf8)!
            let response = HTTPResponse(
                status: 200,
                reason: "OK",
                headers: [:],
                body: body
            )
            
            let serialized = String(data: response.serialize(), encoding: .utf8)!
            #expect(serialized.contains("Content-Length: \(body.count)"))
        }
    }
    
    @Test("HTTPResponse preserves custom headers")
    func testHTTPResponseCustomHeaders() {
        let response = HTTPResponse(
            status: 200,
            reason: "OK",
            headers: [
                "X-Custom-Header": "custom-value",
                "Cache-Control": "no-cache",
                "X-Request-Id": "abc-123"
            ],
            body: Data()
        )
        
        let serialized = String(data: response.serialize(), encoding: .utf8)!
        
        #expect(serialized.contains("X-Custom-Header: custom-value"))
        #expect(serialized.contains("Cache-Control: no-cache"))
        #expect(serialized.contains("X-Request-Id: abc-123"))
    }
    
    @Test("HTTPResponse handles binary body")
    func testHTTPResponseBinaryBody() {
        let binaryData = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        let response = HTTPResponse(
            status: 200,
            reason: "OK",
            headers: ["Content-Type": "application/octet-stream"],
            body: binaryData
        )
        
        let serialized = response.serialize()
        
        // Check that the binary data is at the end
        #expect(serialized.suffix(binaryData.count) == binaryData)
    }
    
    // MARK: - HTTPParser Tests
    
    @Test("HTTPParser parses complete GET request")
    func testParserGETRequest() {
        let requestData = """
            GET /api/users?page=1 HTTP/1.1\r
            Host: example.com\r
            Accept: application/json\r
            \r
            
            """.data(using: .utf8)!
        
        let request = HTTPParser.parse(data: requestData)
        
        #expect(request != nil)
        #expect(request?.method == "GET")
        #expect(request?.path == "/api/users?page=1")
        #expect(request?.headers["Host"] == "example.com")
        #expect(request?.headers["Accept"] == "application/json")
    }
    
    @Test("HTTPParser parses POST request with JSON body")
    func testParserPOSTWithBody() {
        let jsonBody = #"{"name":"John","email":"john@example.com"}"#
        let requestData = """
            POST /api/users HTTP/1.1\r
            Host: example.com\r
            Content-Type: application/json\r
            Content-Length: \(jsonBody.count)\r
            \r
            \(jsonBody)
            """.data(using: .utf8)!
        
        let request = HTTPParser.parse(data: requestData)
        
        #expect(request != nil)
        #expect(request?.method == "POST")
        #expect(request?.path == "/api/users")
        #expect(request?.headers["Content-Type"] == "application/json")
        
        let bodyString = String(data: request?.body ?? Data(), encoding: .utf8)
        #expect(bodyString?.contains("John") == true)
    }
    
    @Test("HTTPParser handles various HTTP methods")
    func testParserHTTPMethods() {
        let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
        
        for method in methods {
            let requestData = "\(method) /test HTTP/1.1\r\nHost: example.com\r\n\r\n".data(using: .utf8)!
            let request = HTTPParser.parse(data: requestData)
            
            #expect(request != nil)
            #expect(request?.method == method)
        }
    }
    
    @Test("HTTPParser returns nil for malformed requests")
    func testParserMalformedRequests() {
        let malformedRequests = [
            "not http at all",
            "GET",
            "GET /path",
            "INVALID /path HTTP/1.1",
            ""
        ]
        
        for requestString in malformedRequests {
            let request = HTTPParser.parse(data: requestString.data(using: .utf8)!)
            #expect(request == nil, "Should return nil for: \(requestString)")
        }
    }
    
    @Test("HTTPParser handles paths with special characters")
    func testParserSpecialPaths() {
        let paths = [
            "/path/with%20spaces",
            "/path?query=value&other=123",
            "/path#fragment",
            "/path/with/many/segments",
            "/"
        ]
        
        for path in paths {
            let requestData = "GET \(path) HTTP/1.1\r\nHost: example.com\r\n\r\n".data(using: .utf8)!
            let request = HTTPParser.parse(data: requestData)
            
            #expect(request != nil)
            #expect(request?.path == path)
        }
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Request and response round-trip works correctly")
    func testRequestResponseRoundTrip() {
        // Simulate a request
        let requestData = """
            GET /api/status HTTP/1.1\r
            Host: localhost:8080\r
            Accept: application/json\r
            \r
            
            """.data(using: .utf8)!
        
        let request = HTTPParser.parse(data: requestData)
        #expect(request != nil)
        
        // Create a response
        let responseBody = #"{"status":"ok","uptime":12345}"#
        let response = HTTPResponse(
            status: 200,
            reason: "OK",
            headers: ["Content-Type": "application/json"],
            body: responseBody.data(using: .utf8)!
        )
        
        let serialized = response.serialize()
        let serializedString = String(data: serialized, encoding: .utf8)!
        
        #expect(serializedString.contains("HTTP/1.1 200 OK"))
        #expect(serializedString.contains(responseBody))
    }
}
