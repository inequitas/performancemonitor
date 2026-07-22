#include "include/CNVMeSMART.h"

#include <string.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>

// Tries each of these IOKit classes in turn: "IOEmbeddedNVMeBlockDevice" is
// the internal SSD on Apple Silicon Macs; "IONVMeBlockDevice" covers Intel
// Macs and some external NVMe enclosures. Neither existing (or the SMART
// interface failing to attach) is not an error — it just means no data.
static const char *kCandidateClasses[] = {
    "IOEmbeddedNVMeBlockDevice",
    "IONVMeBlockDevice"
};

static bool readFromService(io_service_t service, CNVMeSMARTResult *out) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(service,
                                                          kIONVMeSMARTUserClientTypeID,
                                                          kIOCFPlugInInterfaceID,
                                                          &plugin,
                                                          &score);
    if (kr != KERN_SUCCESS || !plugin) {
        return false;
    }

    IONVMeSMARTInterface **smart = NULL;
    HRESULT hres = (*plugin)->QueryInterface(plugin,
                        CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID),
                        (LPVOID *)&smart);
    (*plugin)->Release(plugin);

    if (hres != S_OK || !smart) {
        return false;
    }

    NVMeSMARTData data;
    memset(&data, 0, sizeof(data));
    IOReturn ret = (*smart)->SMARTReadData(smart, &data);
    (*smart)->Release(smart);

    if (ret != kIOReturnSuccess) {
        return false;
    }

    out->success = true;
    out->percentageUsed = data.PERCENTAGE_USED;
    out->availableSparePercent = data.AVAILABLE_SPARE;
    out->dataUnitsWritten = data.DATA_UNITS_WRITTEN[0];
    out->powerOnHours = data.POWER_ON_HOURS[0];
    return true;
}

CNVMeSMARTResult CNVMeSMARTRead(void) {
    CNVMeSMARTResult result;
    memset(&result, 0, sizeof(result));

    for (size_t i = 0; i < sizeof(kCandidateClasses) / sizeof(kCandidateClasses[0]); i++) {
        io_iterator_t iter = 0;
        CFDictionaryRef matching = IOServiceMatching(kCandidateClasses[i]);
        if (!matching) continue;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) != KERN_SUCCESS) {
            continue;
        }

        io_service_t service;
        while ((service = IOIteratorNext(iter))) {
            bool ok = readFromService(service, &result);
            IOObjectRelease(service);
            if (ok) {
                IOObjectRelease(iter);
                return result;
            }
        }
        IOObjectRelease(iter);
    }

    return result; // success == false
}
