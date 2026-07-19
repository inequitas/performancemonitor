import Testing
@testable import PerformanceAppCore

@Suite("SMARTParser")
struct SMARTParserTests {

    private let sample = """
       Device Identifier:        disk0
       Device Node:              /dev/disk0
       Media Name:               APPLE SSD AP1024
       SMART Status:             Verified
       Disk Size:                1.0 TB
    """

    @Test func extractsVerified() {
        #expect(SMARTParser.parse(sample) == "Verified")
    }

    @Test func extractsMultiWordStatus() {
        let notSupported = "   SMART Status:             Not Supported\n"
        #expect(SMARTParser.parse(notSupported) == "Not Supported")
    }

    @Test func missingLineReturnsNil() {
        let noSmart = """
           Device Identifier:        disk0
           Disk Size:                1.0 TB
        """
        #expect(SMARTParser.parse(noSmart) == nil)
    }

    @Test func emptyOutputReturnsNil() {
        #expect(SMARTParser.parse("") == nil)
    }

    @Test func whitespaceIsTrimmed() {
        let padded = "SMART Status:\t   Verified   "
        #expect(SMARTParser.parse(padded) == "Verified")
    }
}
