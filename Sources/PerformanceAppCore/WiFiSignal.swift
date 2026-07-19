import Foundation

/// Pure RSSI → signal-bar-count → label mapping, extracted from the
/// `WiFiSignalBars` SwiftUI view so it can be unit tested without SwiftUI.
public enum WiFiSignal {
    public static func bars(forRSSI rssi: Int) -> Int {
        if rssi >= -50 { return 4 }
        if rssi >= -65 { return 3 }
        if rssi >= -75 { return 2 }
        return 1
    }

    public static func label(forBars bars: Int) -> String {
        switch bars {
        case 4: return "Excellent"
        case 3: return "Good"
        case 2: return "Fair"
        default: return "Weak"
        }
    }
}
