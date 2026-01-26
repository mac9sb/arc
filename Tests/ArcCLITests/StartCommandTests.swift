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

    @Test("StartCommand accepts process-name flag")
    func testStartCommandAcceptsProcessNameFlag() {
        do {
            let command = try StartCommand.parse(["--process-name", "demo-arc"])
            #expect(command.processName == "demo-arc")
        } catch {
            #expect(Bool(false), "Expected process-name flag to parse: \(error)")
        }
    }
}
