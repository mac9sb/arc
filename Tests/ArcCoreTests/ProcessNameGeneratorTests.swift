import Foundation
import Testing

@testable import ArcCore

@Suite("ProcessNameGenerator Tests")
struct ProcessNameGeneratorTests {
    @Test("Generate creates valid process name")
    func testGenerate() {
        let name = ProcessNameGenerator.generate()
        
        // Should be in format "adjective-noun"
        #expect(name.contains("-"))
        let parts = name.split(separator: "-")
        #expect(parts.count == 2)
        #expect(!parts[0].isEmpty)
        #expect(!parts[1].isEmpty)
        
        // Should be valid
        #expect(ProcessNameGenerator.isValid(name: name))
    }
    
    @Test("GenerateUnique excludes existing names")
    func testGenerateUnique() {
        let existing = Set(["happy-panda", "bright-lighthouse", "mellow-falcon"])
        let name = ProcessNameGenerator.generateUnique(excluding: existing)
        
        #expect(!existing.contains(name))
        #expect(ProcessNameGenerator.isValid(name: name))
    }
    
    @Test("IsValid validates correct names")
    func testIsValidCorrectNames() {
        let validNames = [
            "happy-panda",
            "bright-lighthouse",
            "a",
            "a-b",
            "venue123",
            "my-venue-name"
        ]
        
        for name in validNames {
            #expect(ProcessNameGenerator.isValid(name: name), "\(name) should be valid")
        }
    }
    
    @Test("IsValid rejects invalid names")
    func testIsValidInvalidNames() {
        let invalidNames = [
            "",
            "-",
            "a-",
            "-a",
            "A-B",  // Uppercase
            "my venue",  // Space
            "my@venue",  // Special char
            String(repeating: "a", count: 64)  // Too long
        ]
        
        for name in invalidNames {
            #expect(!ProcessNameGenerator.isValid(name: name), "\(name) should be invalid")
        }
    }
    
    @Test("Sanitize converts invalid names to valid")
    func testSanitize() {
        let testCases = [
            ("My Venue", "my-venue"),
            ("VENUE_NAME", "venue-name"),
            ("venue@123", "venue-123"),
            ("  venue  ", "venue")
        ]
        
        for (input, expectedPrefix) in testCases {
            let sanitized = ProcessNameGenerator.sanitize(name: input)
            #expect(ProcessNameGenerator.isValid(name: sanitized))
            // Sanitized should start with expected prefix (may have random suffix if validation fails)
            #expect(sanitized.lowercased().hasPrefix(expectedPrefix) || sanitized.hasPrefix("arc-"))
        }
    }
}
