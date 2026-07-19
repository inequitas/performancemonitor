import Foundation
import Darwin
import IOKit
import PerformanceAppCore

/// Immutable result of one disk sample. `freeGB`/`totalGB` are always valid;
/// `io` is `nil` when the IOKit block-storage query failed, in which case the
/// engine updates only free/total and skips IO rates, SMART and history — exactly
/// as the original `updateDisk` early-returned after setting free/total.
struct DiskSnapshot {
    let freeGB: Double
    let totalGB: Double
    let io: DiskIO?
}

struct DiskIO {
    let readKBps: Double
    let writeKBps: Double
    /// True on the sample where the SMART status should be (re)fetched. The
    /// engine fires `fetchSMART()` when this is set, preserving the original
    /// once-at-startup-then-every-5-min cadence.
    let shouldFetchSMART: Bool
}

protocol DiskSampling: AnyObject {
    func sample() -> DiskSnapshot
    /// Runs `diskutil info /dev/disk0` off the main thread and parses the SMART
    /// status. Returns `nil` when the tool could not be launched.
    func fetchSMART() async -> String?
    /// Enumerates mounted volumes (drives the mount/unmount-driven refresh).
    func volumes() -> [VolumeInfo]
}

/// Owns the previous byte counters and the SMART-fetch throttle tick.
/// Extracted verbatim from `MetricsEngine.updateDisk`/`fetchSmartStatus`/`updateVolumes`.
final class DiskSampler: DiskSampling {
    private var previousBytes: (read: UInt64, write: UInt64)?
    private var previousTimestamp: Date?
    private var smartFetchTick = 0

    func sample() -> DiskSnapshot {
        var freeGB: Double = 0
        var totalGB: Double = 0
        var fsStat = statfs()
        if statfs("/", &fsStat) == 0 {
            let blockSize = Double(fsStat.f_bsize)
            totalGB = Double(fsStat.f_blocks) * blockSize / 1_073_741_824
            freeGB = Double(fsStat.f_bavail) * blockSize / 1_073_741_824
        }

        var (totalRead, totalWrite): (UInt64, UInt64) = (0, 0)
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return DiskSnapshot(freeGB: freeGB, totalGB: totalGB, io: nil)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }

            if let read = stats["Bytes (Read)"] as? UInt64 { totalRead += read }
            if let write = stats["Bytes (Write)"] as? UInt64 { totalWrite += write }
        }

        // Fetch SMART once at startup then every 5 min — diskutil is the reliable
        // source on Apple Silicon.
        smartFetchTick += 1
        let shouldFetchSMART = smartFetchTick == 1 || smartFetchTick % 300 == 0

        var readKBps: Double = 0
        var writeKBps: Double = 0
        let now = Date()
        if let prev = previousBytes, let prevTime = previousTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let readDelta = Double(totalRead &- prev.read)
                let writeDelta = Double(totalWrite &- prev.write)
                readKBps = max(readDelta, 0) / elapsed / 1024
                writeKBps = max(writeDelta, 0) / elapsed / 1024
            }
        }
        previousBytes = (totalRead, totalWrite)
        previousTimestamp = now

        return DiskSnapshot(freeGB: freeGB, totalGB: totalGB,
                            io: DiskIO(readKBps: readKBps, writeKBps: writeKBps,
                                       shouldFetchSMART: shouldFetchSMART))
    }

    func fetchSMART() async -> String? {
        await Task.detached(priority: .background) { () -> String? in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            proc.arguments = ["info", "/dev/disk0"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            guard (try? proc.run()) != nil else { return nil }
            proc.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return SMARTParser.parse(out)
        }.value
    }

    func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        return urls.compactMap { url -> VolumeInfo? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity else { return nil }
            let name = values.volumeName ?? url.lastPathComponent
            return VolumeInfo(
                name: name,
                totalGB: Double(total) / 1_073_741_824,
                freeGB: Double(available) / 1_073_741_824,
                isRemovable: values.volumeIsRemovable ?? false
            )
        }
    }
}
