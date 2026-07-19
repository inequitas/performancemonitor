// SMC (System Management Controller) reader/writer — Apple Silicon only.
//
// Struct layout mirrors the Stats app (exelban/stats) which is verified working.
// Critical: keyInfo is a sub-struct with stride 12 (9 data + 3 trailing pad),
// plus an explicit padding: UInt16, which places data8 at byte offset 44.
// Using inline UInt32 fields instead (without sub-struct) puts data8 at 39 —
// the kernel sees command 0 (invalid) and every call silently fails.

import Foundation
import IOKit
import PerformanceAppCore

// MARK: - Public types

struct FanInfo: Identifiable {
    let id:     Int
    let label:  String
    let actual: Int   // RPM
    let min:    Int
    let max:    Int
}

// MARK: - Kernel struct (84 bytes, alignment 4)

private struct SMCKeyData_t {
    struct vers_t {
        var major:    UInt8  = 0
        var minor:    UInt8  = 0
        var build:    UInt8  = 0
        var reserved: UInt8  = 0
        var release:  UInt16 = 0
    } // size 6, alignment 2

    struct LimitData_t {
        var version:   UInt16 = 0
        var length:    UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    } // size 16, alignment 4

    struct keyInfo_t {
        var dataSize:       UInt32 = 0  // IOByteCount32
        var dataType:       UInt32 = 0
        var dataAttributes: UInt8  = 0
    } // size 9, alignment 4, stride 12 (3 bytes trailing pad)

    var key:        UInt32      = 0         // offset  0
    var vers                    = vers_t()   // offset  4  (6 bytes; 2-byte gap follows → pLimit at 12)
    var pLimitData              = LimitData_t() // offset 12 (16 bytes)
    var keyInfo                 = keyInfo_t()   // offset 28 (stride 12 → next at 40)
    var padding:    UInt16      = 0         // offset 40  (explicit pad)
    var result:     UInt8       = 0         // offset 42
    var status:     UInt8       = 0         // offset 43
    var data8:      UInt8       = 0         // offset 44  ← command selector
    // 3 bytes implicit padding to align data32
    var data32:     UInt32      = 0         // offset 48
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
               (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    // offset 52, 32 bytes → total 84
}

private enum SMCCmd: UInt8 {
    case getKeyInfo = 9
    case readKey    = 5
    case readIndex  = 8
}
private let kSMCSuccess: UInt8 = 0

// MARK: - Reader

final class SMCReader: @unchecked Sendable {
    private var conn: io_connect_t = 0
    let isOpen: Bool
    private var cpuTempKeys: [String]? = nil
    private var gpuTempKeys: [String]? = nil
    private var prevCpuReadings: [String: Double] = [:]
    private var prevGpuReadings: [String: Double] = [:]

    init() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleSMC"), &iter) == KERN_SUCCESS else {
            isOpen = false; return
        }
        let service = IOIteratorNext(iter)
        IOObjectRelease(iter)
        guard service != 0 else { isOpen = false; return }
        defer { IOObjectRelease(service) }
        isOpen = IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    // MARK: - Temperatures

    func cpuTemperature() -> Double? {
        // Discover "Tp*" keys once — M1/M2/M3/M4 all have different key counts.
        if cpuTempKeys == nil {
            let found = discoverKeys(prefix: "Tp")
            cpuTempKeys = found.isEmpty ? ["Tp01","Tp05","Tp09","Tp0D"] : found
        }
        return averageTemp(keys: cpuTempKeys ?? [], prev: &prevCpuReadings)
    }

    func gpuTemperature() -> Double? {
        if gpuTempKeys == nil {
            let found = discoverKeys(prefix: "Tg")
            gpuTempKeys = found.isEmpty ? ["Tg05","Tg0D","Tg0P"] : found
        }
        return averageTemp(keys: gpuTempKeys ?? [], prev: &prevGpuReadings)
    }

    // Averages valid temperature readings; uses previous value for keys that return
    // out-of-range data (some Apple Silicon sensors return garbage transiently).
    private func averageTemp(keys: [String], prev: inout [String: Double]) -> Double? {
        var readings: [Double] = []
        for key in keys {
            let t = readTemperature(key)
            if let t, t > 10, t < 120 {
                prev[key] = t
                readings.append(t)
            } else if let saved = prev[key] {
                readings.append(saved)
            }
        }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    // MARK: - Fans

    func fanCount() -> Int {
        guard let b = readBytes("FNum"), !b.isEmpty else { return 0 }
        return Int(b[0])
    }

    func fans() -> [FanInfo] {
        let n = fanCount()
        let labels: [String] = n == 2 ? ["Left", "Right"] : (0..<n).map { "Fan \($0 + 1)" }
        return (0..<n).compactMap { i in
            guard let act = readRPM("F\(i)Ac"),
                  let mn  = readRPM("F\(i)Mn"),
                  let mx  = readRPM("F\(i)Mx") else { return nil }
            return FanInfo(id: i, label: labels[i], actual: act, min: mn, max: mx)
        }
    }

    // Returns all readable temperature sensors as (key, celsius) pairs, sorted by key.
    // Filters out keys that return out-of-range values (1–130 °C).
    func readAllTemperatures() -> [(key: String, value: Double)] {
        guard let countVal = readDouble("#KEY") else { return [] }
        let count = Int(countVal)
        var result: [(key: String, value: Double)] = []
        for i in 0..<count {
            var input  = SMCKeyData_t()
            var output = SMCKeyData_t()
            input.data8  = SMCCmd.readIndex.rawValue
            input.data32 = UInt32(i)
            guard callRaw(&input, &output) == kSMCSuccess else { continue }
            let k = fourCC(output.key)
            guard k.hasPrefix("T"), k.count == 4 else { continue }
            if let temp = readTemperature(k), temp > 1, temp < 130 {
                result.append((key: k, value: temp))
            }
        }
        return result.sorted { $0.key < $1.key }
    }

    // MARK: - Key discovery  (fan control intentionally omitted — SMC writes
    // return kIOReturnError for unprivileged processes; a root-level XPC helper
    // is required, as confirmed by probing against the SMC directly)

    func discoverKeys(prefix: String) -> [String] {
        guard let countVal = readDouble("#KEY") else { return [] }
        let count = Int(countVal)
        var result: [String] = []
        for i in 0..<count {
            var input  = SMCKeyData_t()
            var output = SMCKeyData_t()
            input.data8  = SMCCmd.readIndex.rawValue
            input.data32 = UInt32(i)
            guard callRaw(&input, &output) == kSMCSuccess else { continue }
            let k = fourCC(output.key)
            if k.hasPrefix(prefix) { result.append(k) }
        }
        return result
    }

    // MARK: - Private helpers

    private struct SMCVal {
        var key:      String
        var dataSize: UInt32 = 0  // matches IOByteCount32 in keyInfo_t
        var dataType: String = ""
        var bytes:    [UInt8] = Array(repeating: 0, count: 32)
    }

    private func readVal(_ key: String) -> SMCVal? {
        var input  = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key   = encode(key)
        input.data8 = SMCCmd.getKeyInfo.rawValue
        guard callRaw(&input, &output) == kSMCSuccess else { return nil }
        let size     = output.keyInfo.dataSize
        let typeCode = output.keyInfo.dataType  // save from getKeyInfo — kernel zeros this on readKey
        guard size > 0 else { return nil }
        input.keyInfo.dataSize = size
        input.keyInfo.dataType = typeCode
        input.data8 = SMCCmd.readKey.rawValue
        guard callRaw(&input, &output) == kSMCSuccess else { return nil }
        var val = SMCVal(key: key)
        val.dataSize = size
        val.dataType = fourCC(typeCode)
        val.bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(size))) }
        return val
    }

    private func readDouble(_ key: String) -> Double? {
        guard let val = readVal(key), val.dataSize > 0 else { return nil }
        switch val.dataType {
        case "ui8 ": return Double(val.bytes[0])
        case "ui16": return Double(UInt16(val.bytes[0]) << 8 | UInt16(val.bytes[1]))
        case "ui32": return Double(UInt32(val.bytes[0]) << 24 | UInt32(val.bytes[1]) << 16 |
                                   UInt32(val.bytes[2]) << 8  | UInt32(val.bytes[3]))
        case "sp78": return Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1])) / 256.0
        case "fpe2": return Double(Int(val.bytes[0]) << 6 | Int(val.bytes[1]) >> 2)
        default:     return nil
        }
    }

    // Type-aware temperature reader: handles sp78 (2-byte signed fixed-point)
    // and flt (4-byte IEEE-754 float). Apple Silicon sensors use both formats;
    // blindly reading flt bytes as sp78 produces garbage values like 20/50/80/120.
    private func readTemperature(_ key: String) -> Double? {
        guard let val = readVal(key) else { return nil }
        switch val.dataType {
        case "sp78":
            guard val.dataSize >= 2 else { return nil }
            return Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1])) / 256.0
        case "flt ":
            guard val.dataSize >= 4 else { return nil }
            let bits = UInt32(val.bytes[0]) | UInt32(val.bytes[1]) << 8
                     | UInt32(val.bytes[2]) << 16 | UInt32(val.bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        default:
            return nil
        }
    }

    // Fan RPM keys use either fpe2 (older/Intel) or flt (Apple Silicon).
    // Runtime type check avoids the ~200× decode error when flt bytes are read as fpe2.
    private func readRPM(_ key: String) -> Int? {
        guard let val = readVal(key) else { return nil }
        switch val.dataType {
        case "flt ":
            guard val.dataSize >= 4 else { return nil }
            let bits = UInt32(val.bytes[0]) | UInt32(val.bytes[1]) << 8
                     | UInt32(val.bytes[2]) << 16 | UInt32(val.bytes[3]) << 24
            return Int(Float(bitPattern: bits).rounded())
        case "fpe2":
            guard val.dataSize >= 2 else { return nil }
            return (Int(val.bytes[0]) << 6) | (Int(val.bytes[1]) >> 2)
        default:
            return nil
        }
    }

    private func readBytes(_ key: String) -> [UInt8]? {
        guard let val = readVal(key) else { return nil }
        return val.bytes
    }

    @discardableResult
    private func callRaw(_ input: inout SMCKeyData_t, _ output: inout SMCKeyData_t) -> UInt8 {
        let size = MemoryLayout<SMCKeyData_t>.stride
        var outSize = size
        let kr = IOConnectCallStructMethod(conn, 2, &input, size, &output, &outSize)
        guard kr == KERN_SUCCESS else { return 0xFF }
        return output.result
    }

    private func encode(_ key: String) -> UInt32 {
        FourCC.encode(key)
    }

    private func fourCC(_ code: UInt32) -> String {
        FourCC.decode(code)
    }
}
