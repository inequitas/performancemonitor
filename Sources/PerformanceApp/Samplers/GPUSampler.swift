import Foundation
import IOKit
import Metal

/// Static GPU device information, read once at launch.
struct GPUInfo {
    let name: String
    let recommendedMemoryGB: Double
    let isLowPower: Bool
    let isRemovable: Bool
}

@MainActor
protocol GPUSampling: AnyObject {
    /// Static device info from Metal, or `nil` if no default device exists.
    /// Read once at launch — stays on the calling actor.
    func staticInfo() -> GPUInfo?
    /// Current GPU utilization (0–100) off the main thread, or `nil` when no
    /// accelerator reported a usable statistic or a previous call is still in
    /// flight — engine then keeps its previous value.
    func usage() async -> Double?
}

/// GPU reader; the IOKit accelerator walk runs detached from the main thread.
/// Extracted verbatim from `MetricsEngine.updateGPUInfo` and `updateGPUUsage`.
@MainActor
final class GPUSampler: GPUSampling {
    private var inFlight = false

    func staticInfo() -> GPUInfo? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return GPUInfo(name: device.name,
                       recommendedMemoryGB: Double(device.recommendedMaxWorkingSetSize) / 1_073_741_824,
                       isLowPower: device.isLowPower,
                       isRemovable: device.isRemovable)
    }

    func usage() async -> Double? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }
        return await Task.detached(priority: .utility) { () -> Double? in
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault,
                  IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                var props: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let dict = props?.takeRetainedValue() as? [String: Any],
                      let stats = dict["PerformanceStatistics"] as? [String: Any] else { continue }

                // Apple Silicon: "GPU Core Utilization" is a Double in [0, 1]
                if let util = stats["GPU Core Utilization"] as? Double {
                    return util * 100
                }
                // Fallback (discrete GPUs): "Device Utilization %" is an Int
                if let util = stats["Device Utilization %"] as? Int {
                    return Double(util)
                }
            }
            return nil
        }.value
    }
}
