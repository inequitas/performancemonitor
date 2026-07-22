import Foundation

/// Parsed NVMe wear-level ("SMART/Health Information", Log ID 02h) metrics for
/// display. Raw values are read via the public IOKit CFPlugIn interface
/// `IONVMeSMARTInterface` (NVMeSMARTLib.plugin) — see `NVMeSMARTReader` in the
/// app target. This type holds only the fields the UI shows; everything else
/// in the 512-byte log page is ignored.
public struct NVMeWearInfo: Equatable, Sendable {
    /// Percentage of the drive's rated endurance consumed. Per spec this may
    /// read >100 once the drive has exceeded its rated life.
    public let percentageUsed: Int
    /// Remaining spare capacity, normalized to 100% = "full spare".
    public let availableSparePercent: Int
    /// Cumulative bytes written to the NAND, converted from the NVMe log's
    /// "Data Units Written" field.
    public let totalBytesWritten: UInt64
    public let powerOnHours: UInt64

    public init(percentageUsed: Int, availableSparePercent: Int, totalBytesWritten: UInt64, powerOnHours: UInt64) {
        self.percentageUsed = percentageUsed
        self.availableSparePercent = availableSparePercent
        self.totalBytesWritten = totalBytesWritten
        self.powerOnHours = powerOnHours
    }

    /// Total bytes written, in terabytes (TB = 10^12 bytes, matching how SSD
    /// vendors publish TBW ratings).
    public var totalBytesWrittenTB: Double {
        Double(totalBytesWritten) / 1_000_000_000_000
    }
}

/// Pure conversion logic for the NVMe SMART/Health log page, kept separate
/// from the IOKit reading code so it's testable without hardware access.
public enum NVMeSMARTConverter {
    /// The NVMe spec reports "Data Units Written"/"Data Units Read" in units
    /// of 1000 * 512 bytes = 512,000 bytes — NOT raw bytes and NOT 512-byte
    /// sectors. See NVM Express Base Specification §5.14.1.2. Overflow-safe:
    /// clamps to `UInt64.max` rather than wrapping for implausibly large inputs.
    public static func dataUnitsToBytes(_ units: UInt64) -> UInt64 {
        let (result, overflow) = units.multipliedReportingOverflow(by: 512_000)
        return overflow ? UInt64.max : result
    }

    public static func makeWearInfo(
        percentageUsed: Int,
        availableSparePercent: Int,
        dataUnitsWritten: UInt64,
        powerOnHours: UInt64
    ) -> NVMeWearInfo {
        NVMeWearInfo(
            percentageUsed: percentageUsed,
            availableSparePercent: availableSparePercent,
            totalBytesWritten: dataUnitsToBytes(dataUnitsWritten),
            powerOnHours: powerOnHours
        )
    }
}
