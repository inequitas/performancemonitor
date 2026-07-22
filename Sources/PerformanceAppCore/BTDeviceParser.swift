import Foundation

/// Extracted from `BluetoothSampler`.
public struct BTBatteryInfo: Equatable {
    public var main: Int?
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    
    public init(main: Int? = nil, left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil) {
        self.main = main
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
    }
}

/// Pure parser for the output of `system_profiler SPBluetoothDataType -json`.
///
/// Extracted from `BluetoothSampler` in the Part-B decomposition.
public enum BTDeviceParser {
    public static func parse(_ data: Data) -> [String: BTBatteryInfo]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let btArray = json["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

        func parsePct(_ info: [String: Any], _ key: String) -> Int? {
            guard let s = info[key] as? String else { return nil }
            return Int(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        }

        var cache: [String: BTBatteryInfo] = [:]
        for entry in btArray {
            for listKey in ["device_connected", "device_not_connected"] {
                guard let deviceList = entry[listKey] as? [[String: Any]] else { continue }
                for deviceDict in deviceList {
                    for (_, infoAny) in deviceDict {
                        guard let info = infoAny as? [String: Any],
                              let addr = info["device_address"] as? String else { continue }
                        let norm = addr.lowercased().replacingOccurrences(of: "-", with: ":")
                        cache[norm] = BTBatteryInfo(
                            main:      parsePct(info, "device_batteryLevel"),
                            left:      parsePct(info, "device_batteryLevelLeft"),
                            right:     parsePct(info, "device_batteryLevelRight"),
                            caseLevel: parsePct(info, "device_batteryLevelCase")
                        )
                    }
                }
            }
        }
        return cache
    }
}
