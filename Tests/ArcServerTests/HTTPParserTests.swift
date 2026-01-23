import Foundation
import Testing

@testable import ArcServer

@Suite("HTTPParser Tests")
struct HTTPParserTests {
    @Test("Parse valid GET request")
    func testParseValidGETRequest() {
        let requestString = "GET /path HTTP/1.1\r\nHost: example.com\r\nUser-Agent: Test\r\n\r\n"
        let requestData = requestString.data(using: .utf8)!

        let request = HTTPParser.parse(data: requestData)

        #expect(request != nil)
        #expect(request?.method == "GET")
        #expect(request?.path == "/path")
        #expect(request?.headers["Host"] == "example.com")
        #expect(request?.headers["User-Agent"] == "Test")
    }

    @Test("Parse request with body")
    func testParseRequestWithBody() {
        let requestData = """
            POST /api/data HTTP/1.1\r
            Content-Type: application/json\r
            Content-Length: 13\r
            \r
            {"key":"value"}
            """.data(using: .utf8)!

        let request = HTTPParser.parse(data: requestData)

        #expect(request != nil)
        #expect(request?.method == "POST")
        #expect(request?.path == "/api/data")
        let bodyString = String(data: request?.body ?? Data(), encoding: .utf8)
        #expect(bodyString?.contains("key") == true)
    }

    @Test("Parse returns nil for invalid data")
    func testParseInvalidData() {
        let invalidData = "not http".data(using: .utf8)!
        let request = HTTPParser.parse(data: invalidData)
        #expect(request == nil)
    }
}
