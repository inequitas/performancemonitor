import Testing
@testable import PerformanceAppCore

@Suite("NVMeSMARTConverter")
struct NVMeSMARTConverterTests {

    @Test func dataUnitsToBytesAppliesThe512000Multiplier() {
        // NVMe spec: 1 "data unit" = 1000 * 512 bytes = 512,000 bytes.
        #expect(NVMeSMARTConverter.dataUnitsToBytes(1) == 512_000)
        #expect(NVMeSMARTConverter.dataUnitsToBytes(0) == 0)
    }

    @Test func dataUnitsToBytesMatchesObservedMachineValue() {
        // Value observed on the research-spike test machine: ~30.4 TB written.
        let bytes = NVMeSMARTConverter.dataUnitsToBytes(59_341_677)
        let tb = Double(bytes) / 1_000_000_000_000
        #expect(abs(tb - 30.383) < 0.001)
    }

    @Test func dataUnitsToBytesClampsOnOverflowInsteadOfWrapping() {
        #expect(NVMeSMARTConverter.dataUnitsToBytes(UInt64.max) == UInt64.max)
    }

    @Test func makeWearInfoConvertsDataUnitsToTotalBytesWritten() {
        let info = NVMeSMARTConverter.makeWearInfo(
            percentageUsed: 1,
            availableSparePercent: 100,
            dataUnitsWritten: 59_341_677,
            powerOnHours: 1040
        )
        #expect(info.percentageUsed == 1)
        #expect(info.availableSparePercent == 100)
        #expect(info.powerOnHours == 1040)
        #expect(abs(info.totalBytesWrittenTB - 30.383) < 0.001)
    }

    @Test func totalBytesWrittenTBConvertsUsingDecimalTerabytes() {
        let info = NVMeWearInfo(percentageUsed: 5, availableSparePercent: 95,
                                 totalBytesWritten: 1_000_000_000_000, powerOnHours: 10)
        #expect(info.totalBytesWrittenTB == 1.0)
    }
}
