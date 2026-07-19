import Testing
@testable import PerformanceAppCore

@Suite("SubnetMask")
struct SubnetMaskTests {

    @Test func nilPrefixReturnsNil() {
        #expect(SubnetMask.string(forPrefixLength: nil) == nil)
    }

    @Test func zeroPrefixReturnsNil() {
        // Matches the original `guard let p = prefixLength, p > 0` behavior:
        // a /0 prefix is treated the same as "unknown", not "0.0.0.0".
        #expect(SubnetMask.string(forPrefixLength: 0) == nil)
    }

    @Test func commonPrefixLengths() {
        #expect(SubnetMask.string(forPrefixLength: 8) == "255.0.0.0")
        #expect(SubnetMask.string(forPrefixLength: 16) == "255.255.0.0")
        #expect(SubnetMask.string(forPrefixLength: 24) == "255.255.255.0")
    }

    @Test func nonByteAlignedPrefix() {
        #expect(SubnetMask.string(forPrefixLength: 25) == "255.255.255.128")
        #expect(SubnetMask.string(forPrefixLength: 30) == "255.255.255.252")
    }

    @Test func fullPrefixIsAllOnes() {
        #expect(SubnetMask.string(forPrefixLength: 32) == "255.255.255.255")
    }

    @Test func overlongPrefixClampsLikeThirtyTwo() {
        // Original code: `p >= 32 ? UInt32.max : ...` — anything >= 32 behaves like /32.
        #expect(SubnetMask.string(forPrefixLength: 33) == "255.255.255.255")
    }

    @Test func minimalNonZeroPrefix() {
        #expect(SubnetMask.string(forPrefixLength: 1) == "128.0.0.0")
    }
}
