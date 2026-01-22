import Foundation
import Testing

@testable import ArcServer

@Suite("HTTPResponse Tests")
struct HTTPResponseTests {
    @Test("Serialize creates valid HTTP response")
    func testSerialize() {
        let response = HTTPResponse(
            status: 200,
            reason: "OK",
            headers: ["Content-Type": "text/html"],
            body: "Hello World".data(using: .utf8)!
        )
        
        let serialized = response.serialize()
        let serializedString = String(data: serialized, encoding: .utf8) ?? ""
        
        #expect(serializedString.contains("HTTP/1.1 200 OK"))
        #expect(serializedString.contains("Content-Type: text/html"))
        #expect(serializedString.contains("Content-Length: 11"))
        #expect(serializedString.contains("Hello World"))
    }
    
    @Test("Serialize includes Content-Length automatically")
    func testSerializeIncludesContentLength() {
        let body = "Test Body".data(using: .utf8)!
        let response = HTTPResponse(
            status: 404,
            reason: "Not Found",
            headers: [:],
            body: body
        )
        
        let serialized = response.serialize()
        let serializedString = String(data: serialized, encoding: .utf8) ?? ""
        
        #expect(serializedString.contains("Content-Length: 9"))
    }
}
