#include "include/CIOReport.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>

// ---- IOReport private API signatures ----------------------------------------
// IOReport is an OS-private framework with no public header. The symbols below
// live in /usr/lib/libIOReport.dylib and are resolved at runtime via dlsym.
// Signatures are the widely-used community reverse-engineering (macmon/asitop).
// Nothing here is hard-coded to a SoC generation: channels are enumerated and
// matched by name at sample time.
typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;
typedef int (^ioreport_iterate_block)(CFDictionaryRef ch);

typedef CFMutableDictionaryRef (*fn_CopyChannelsInGroup)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef IOReportSubscriptionRef (*fn_CreateSubscription)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*fn_CreateSamples)(IOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef);
typedef CFStringRef (*fn_ChannelGetChannelName)(CFDictionaryRef);
typedef CFStringRef (*fn_ChannelGetUnitLabel)(CFDictionaryRef);
typedef int64_t (*fn_SimpleGetIntegerValue)(CFDictionaryRef, int);
typedef void (*fn_Iterate)(CFDictionaryRef, ioreport_iterate_block);

struct CIOReportReader {
    void *dylib;
    fn_CopyChannelsInGroup   copyChannelsInGroup;
    fn_CreateSubscription    createSubscription;
    fn_CreateSamples         createSamples;
    fn_ChannelGetChannelName getChannelName;
    fn_ChannelGetUnitLabel   getUnitLabel;
    fn_SimpleGetIntegerValue getIntegerValue;
    fn_Iterate               iterate;

    IOReportSubscriptionRef  subscription;
    CFMutableDictionaryRef   subscribedChannels;
};

// Per-domain accumulator used while iterating one sample. Energy channels whose
// name contains "Energy" (the canonical accumulators, e.g. "GPU Energy") take
// precedence over any bare same-prefix channel so we never double-count a rail
// that is exposed under two names.
typedef struct {
    bool                energyNamedPresent;
    int64_t             energyNamedSum;
    CIOReportEnergyUnit energyNamedUnit;
    bool                fallbackPresent;
    int64_t             fallbackSum;
    CIOReportEnergyUnit fallbackUnit;
} DomainAccum;

static CIOReportEnergyUnit unit_from_label(CFStringRef label) {
    if (!label) return CIOReportUnitUnknown;
    char buf[32];
    if (!CFStringGetCString(label, buf, sizeof buf, kCFStringEncodingUTF8))
        return CIOReportUnitUnknown;
    if (strcasecmp(buf, "mJ") == 0) return CIOReportUnitMillijoule;
    if (strcasecmp(buf, "uJ") == 0) return CIOReportUnitMicrojoule;
    // Some locales encode micro as the UTF-8 "µ" (0xC2 0xB5) prefix.
    if (strcasecmp(buf, "\xC2\xB5J") == 0) return CIOReportUnitMicrojoule;
    if (strcasecmp(buf, "nJ") == 0) return CIOReportUnitNanojoule;
    return CIOReportUnitUnknown;
}

static void accum_add(DomainAccum *d, bool named, int64_t v, CIOReportEnergyUnit u) {
    if (named) {
        d->energyNamedSum += v;
        d->energyNamedUnit = u;
        d->energyNamedPresent = true;
    } else {
        d->fallbackSum += v;
        d->fallbackUnit = u;
        d->fallbackPresent = true;
    }
}

static void accum_finalize(const DomainAccum *d, CIOReportDomain *out) {
    if (d->energyNamedPresent) {
        out->present = true;
        out->energy  = d->energyNamedSum;
        out->unit    = d->energyNamedUnit;
    } else if (d->fallbackPresent) {
        out->present = true;
        out->energy  = d->fallbackSum;
        out->unit    = d->fallbackUnit;
    } else {
        out->present = false;
        out->energy  = 0;
        out->unit    = CIOReportUnitUnknown;
    }
}

CIOReportReader *CIOReportOpen(void) {
    void *h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW);
    if (!h) return NULL;

    CIOReportReader *r = calloc(1, sizeof(*r));
    if (!r) { dlclose(h); return NULL; }
    r->dylib = h;

    r->copyChannelsInGroup = (fn_CopyChannelsInGroup)dlsym(h, "IOReportCopyChannelsInGroup");
    r->createSubscription  = (fn_CreateSubscription)dlsym(h, "IOReportCreateSubscription");
    r->createSamples       = (fn_CreateSamples)dlsym(h, "IOReportCreateSamples");
    r->getChannelName      = (fn_ChannelGetChannelName)dlsym(h, "IOReportChannelGetChannelName");
    r->getUnitLabel        = (fn_ChannelGetUnitLabel)dlsym(h, "IOReportChannelGetUnitLabel");
    r->getIntegerValue     = (fn_SimpleGetIntegerValue)dlsym(h, "IOReportSimpleGetIntegerValue");
    r->iterate             = (fn_Iterate)dlsym(h, "IOReportIterate");

    if (!r->copyChannelsInGroup || !r->createSubscription || !r->createSamples ||
        !r->getChannelName || !r->getUnitLabel || !r->getIntegerValue || !r->iterate) {
        CIOReportClose(r);
        return NULL;
    }

    CFStringRef group = CFStringCreateWithCString(NULL, "Energy Model", kCFStringEncodingUTF8);
    CFMutableDictionaryRef channels = r->copyChannelsInGroup(group, NULL, 0, 0, 0);
    CFRelease(group);
    if (!channels) { CIOReportClose(r); return NULL; }

    CFMutableDictionaryRef subscribed = NULL;
    IOReportSubscriptionRef sub = r->createSubscription(NULL, channels, &subscribed, 0, NULL);
    CFRelease(channels);
    if (!sub || !subscribed) {
        if (subscribed) CFRelease(subscribed);
        CIOReportClose(r);
        return NULL;
    }
    r->subscription = sub;
    r->subscribedChannels = subscribed;
    return r;
}

bool CIOReportSampleRead(CIOReportReader *reader, CIOReportSample *out) {
    if (!out) return false;
    memset(out, 0, sizeof(*out));
    if (!reader || !reader->subscription) return false;

    CFDictionaryRef sample = reader->createSamples(reader->subscription,
                                                   reader->subscribedChannels, NULL);
    if (!sample) return false;

    // `__block` so the iterate block writes through to these, rather than
    // mutating its own const captured copies (which finalize would then ignore).
    __block DomainAccum cpu = {0}, ecpu = {0}, pcpu = {0}, gpu = {0}, ane = {0}, dram = {0};
    __block bool any = false;

    reader->iterate(sample, ^int(CFDictionaryRef ch) {
        int64_t v = reader->getIntegerValue(ch, 0);
        if (v == INT64_MIN) return 0; // non-simple (state/array) channel — skip
        CIOReportEnergyUnit u = unit_from_label(reader->getUnitLabel(ch));
        if (u == CIOReportUnitUnknown) return 0; // not an energy channel — skip

        CFStringRef nameRef = reader->getChannelName(ch);
        char name[128];
        if (!nameRef || !CFStringGetCString(nameRef, name, sizeof name, kCFStringEncodingUTF8))
            return 0;

        bool named = (strcasestr(name, "Energy") != NULL);
        // Order matters: ECPU/PCPU both contain "CPU", so test them first.
        if (strcasestr(name, "ECPU"))      { accum_add(&ecpu, named, v, u); any = true; }
        else if (strcasestr(name, "PCPU")) { accum_add(&pcpu, named, v, u); any = true; }
        else if (strcasestr(name, "CPU"))  { accum_add(&cpu,  named, v, u); any = true; }
        if (strcasestr(name, "GPU"))       { accum_add(&gpu,  named, v, u); any = true; }
        if (strcasestr(name, "ANE"))       { accum_add(&ane,  named, v, u); any = true; }
        if (strcasestr(name, "DRAM"))      { accum_add(&dram, named, v, u); any = true; }
        return 0; // kIOReportIterOk
    });

    CFRelease(sample);

    accum_finalize(&cpu,  &out->cpu);
    accum_finalize(&ecpu, &out->ecpu);
    accum_finalize(&pcpu, &out->pcpu);
    accum_finalize(&gpu,  &out->gpu);
    accum_finalize(&ane,  &out->ane);
    accum_finalize(&dram, &out->dram);
    out->valid = any;
    return any;
}

void CIOReportClose(CIOReportReader *reader) {
    if (!reader) return;
    if (reader->subscribedChannels) CFRelease(reader->subscribedChannels);
    if (reader->subscription) CFRelease((CFTypeRef)reader->subscription);
    if (reader->dylib) dlclose(reader->dylib);
    free(reader);
}
