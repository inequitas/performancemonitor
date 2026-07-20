#ifndef CNVMeSMART_h
#define CNVMeSMART_h

#include <stdint.h>
#include <stdbool.h>

/// Plain-C result of one NVMe SMART/Health log read. Kept free of IOKit/
/// CFPlugIn types (function-pointer COM vtables, CFUUIDBytes) so Swift can
/// import it directly without any interop shims.
typedef struct {
    bool success;
    uint8_t percentageUsed;
    uint8_t availableSparePercent;
    // Low 64 bits of the NVMe log's 128-bit "Data Units Written" counter (in
    // units of 512,000 bytes). Sufficient for any drive size in existence.
    uint64_t dataUnitsWritten;
    uint64_t powerOnHours;
} CNVMeSMARTResult;

/// Reads the NVMe SMART/Health Information log (Log ID 02h) for the internal
/// SSD via the public IOKit CFPlugIn interface `IONVMeSMARTInterface`
/// (NVMeSMARTLib.plugin, declared in
/// <IOKit/storage/nvme/NVMeSMARTLibExternal.h>). Works without root or extra
/// entitlements on Apple Silicon Macs. Returns a result with `success = false`
/// when no compatible NVMe controller is found or the read fails (e.g. an
/// external drive without a matching IOKit class).
CNVMeSMARTResult CNVMeSMARTRead(void);

#endif /* CNVMeSMART_h */
