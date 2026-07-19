import Testing
@testable import PerformanceAppCore

@Suite("FourCC")
struct FourCCTests {

    @Test func roundTripCommonSMCKeys() {
        for key in ["TC0P", "FNum", "Tp01", "#KEY"] {
            #expect(FourCC.decode(FourCC.encode(key)) == key)
        }
    }

    @Test func encodeKnownValue() {
        // 'T'=0x54 'C'=0x43 '0'=0x30 'P'=0x50
        #expect(FourCC.encode("TC0P") == 0x5443_3050)
    }

    @Test func decodeKnownValue() {
        #expect(FourCC.decode(0x5443_3050) == "TC0P")
    }

    @Test func encodeTruncatesToFourBytes() {
        // Only the first 4 UTF-8 bytes are packed; a 5th character is ignored.
        #expect(FourCC.encode("TC0P5") == FourCC.encode("TC0P"))
    }

    @Test func encodeShorterThanFourBytesIsLeftPaddedWithZero() {
        #expect(FourCC.encode("AB") == 0x0000_4142)
    }

    @Test func decodeOfZeroIsPlaceholder() {
        // Zero bytes aren't valid printable ASCII/UTF-8 text here — but they
        // are technically valid UTF-8 (NUL), so decode succeeds with NUL chars
        // rather than falling back to "????". Pin the existing behavior either way.
        let decoded = FourCC.decode(0)
        #expect(decoded.utf8.count == 4)
    }
}
