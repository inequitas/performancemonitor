#ifndef CIOReport_h
#define CIOReport_h

#include <stdint.h>
#include <stdbool.h>

/// Native energy unit reported by an IOReport "Energy Model" channel. The unit
/// travels with the value so the pure watt conversion (in PerformanceAppCore)
/// can scale mJ vs nJ correctly — different domains use different units (e.g.
/// GPU Energy is reported in nJ while CPU/DRAM are in mJ on current silicon).
typedef enum {
    CIOReportUnitUnknown    = 0,
    CIOReportUnitMillijoule = 1, // mJ
    CIOReportUnitMicrojoule = 2, // uJ
    CIOReportUnitNanojoule  = 3, // nJ
} CIOReportEnergyUnit;

/// One power domain's cumulative energy reading within a single sample.
typedef struct {
    bool                present; // at least one usable channel matched this domain
    int64_t             energy;  // cumulative energy since subscription start, in `unit`
    CIOReportEnergyUnit unit;    // native unit of `energy`
} CIOReportDomain;

/// One sample of the "Energy Model" group. Every energy value is a cumulative
/// (monotonic) counter; the caller differences successive samples and divides
/// by the elapsed time to get power. Fields for domains not present on this
/// hardware/OS are left with `present = false`.
typedef struct {
    bool            valid; // sampling succeeded and at least one domain was present
    CIOReportDomain cpu;   // combined CPU package ("CPU Energy" channel, if the SoC exposes one)
    CIOReportDomain ecpu;  // efficiency-core cluster (E-cores)
    CIOReportDomain pcpu;  // performance-core cluster (P-cores)
    CIOReportDomain gpu;
    CIOReportDomain ane;   // Apple Neural Engine
    CIOReportDomain dram;  // memory controller / DRAM
} CIOReportSample;

/// Opaque handle owning the dlopen'd IOReport functions and the live "Energy
/// Model" subscription. All access is single-threaded (created and used from
/// one background sampler), mirroring how `SMCReader` is used.
typedef struct CIOReportReader CIOReportReader;

/// dlopen()s `/usr/lib/libIOReport.dylib` (the framework path does not resolve
/// in the dyld shared cache), resolves the private symbols, and subscribes to
/// the "Energy Model" channel group. Returns NULL when the dylib, any required
/// symbol, or the group is unavailable — callers treat NULL as "no data" and
/// simply hide the feature. Never aborts.
CIOReportReader *CIOReportOpen(void);

/// Takes one sample of the subscribed group and fills `out` with each domain's
/// cumulative energy. Channels are enumerated at runtime and matched by name
/// substring (nothing is hard-coded to a specific SoC). Channels whose value is
/// INT64_MIN (non-simple/state format) or whose unit is not an energy unit are
/// skipped. Returns false (and sets `out->valid = false`) when sampling fails.
bool CIOReportSampleRead(CIOReportReader *reader, CIOReportSample *out);

/// Releases the subscription and the dlopen handle. Safe to call with NULL.
void CIOReportClose(CIOReportReader *reader);

#endif /* CIOReport_h */
