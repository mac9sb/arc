import Foundation
import Testing

@testable import ArcServer

@Suite("Cloudflared Config Support Tests")
struct CloudflaredConfigSupportTests {
    @Test("Credentials path uses ~/.cloudflared/<uuid>.json")
    func testCredentialsFilePath() {
        let uuid = "test-uuid"
        let path = CloudflaredCredentials.filePath(tunnelUUID: uuid)
        #expect(path.hasSuffix("/.cloudflared/\(uuid).json"))
    }
}
