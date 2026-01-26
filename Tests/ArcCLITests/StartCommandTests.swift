import Testing

@testable import ArcCLI

@Suite("StartCommand Tests")
struct StartCommandTests {
    @Test("StartCommand accepts keep-awake flag")
    func testStartCommandAcceptsKeepAwakeFlag() {
        do {
            _ = try StartCommand.parse(["--keep-awake"])
            #expect(true)
        } catch {
            #expect(Bool(false), "Expected keep-awake flag to parse: \(error)")
        }
    }
}
