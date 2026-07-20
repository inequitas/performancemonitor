// NVMe SMART/wear-level reader — internal SSD, no root required.
//
// The actual IOKit CFPlugIn call (IONVMeSMARTInterface via NVMeSMARTLib.plugin)
// lives in the tiny C target `CNVMeSMART`: that interface is a COM-style
// vtable (IUNKNOWN_C_GUTS) which Swift cannot import cleanly, so the C side
// does the CFPlugIn dance and hands back a plain struct. This type just
// converts that struct into a PerformanceAppCore.NVMeWearInfo.
//
// Confirmed working unprivileged (no sudo, no entitlements) on Apple Silicon
// during the v1.1 1.1c research spike.

import Foundation
import CNVMeSMART
import PerformanceAppCore

final class NVMeSMARTReader: @unchecked Sendable {
    /// Returns `nil` when no compatible NVMe controller is found (e.g. an
    /// external drive without the matching IOKit class) or the read fails.
    func read() -> NVMeWearInfo? {
        let result = CNVMeSMARTRead()
        guard result.success else { return nil }
        return NVMeSMARTConverter.makeWearInfo(
            percentageUsed: Int(result.percentageUsed),
            availableSparePercent: Int(result.availableSparePercent),
            dataUnitsWritten: result.dataUnitsWritten,
            powerOnHours: result.powerOnHours
        )
    }
}
