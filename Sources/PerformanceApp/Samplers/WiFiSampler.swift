import Foundation
import CoreWLAN

/// Result of one Wi-Fi sample.
enum WiFiSnapshot {
    /// Not on Wi-Fi — engine clears SSID/RSSI.
    case clear
    /// Throttled (read <3s ago) — engine leaves SSID/RSSI unchanged.
    case throttled
    /// Fresh reading — engine sets SSID/RSSI.
    case value(ssid: String?, rssi: Int?)
}

protocol WiFiSampling: AnyObject {
    func sample(connectionType: String) -> WiFiSnapshot
}

/// Owns the 3s read throttle. Extracted verbatim from `MetricsEngine.updateWiFiSignal`.
final class WiFiSampler: WiFiSampling {
    private var cacheDate: Date = .distantPast

    func sample(connectionType: String) -> WiFiSnapshot {
        guard connectionType == "Wi-Fi" else {
            cacheDate = .distantPast
            return .clear
        }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) > 3 else { return .throttled }
        cacheDate = now
        let iface = CWWiFiClient.shared().interface()
        let ssid = iface?.ssid()
        let rssi: Int?
        if let value = iface?.rssiValue(), value != 0 {
            rssi = value
        } else {
            rssi = nil
        }
        return .value(ssid: ssid, rssi: rssi)
    }
}
