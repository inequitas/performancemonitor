import Foundation
import Darwin
import AppKit
import CoreWLAN
import SystemConfiguration
import PerformanceAppCore

/// Immutable result of one network sample.
struct NetworkSnapshot {
    let downloadKBps: Double
    let uploadKBps: Double
    let interfaces: [LocalInterface]
    let dnsServers: [String]
    let isVPNActive: Bool
    let vpnIsFortiClient: Bool
}

protocol NetworkSampling: AnyObject {
    /// Enumerates interfaces, computes throughput deltas, resolves gateways/DNS,
    /// and detects VPNs. Returns `nil` if `getifaddrs` fails (engine leaves
    /// network state untouched). `connectionType` is the primary link kind as
    /// reported by the engine's path monitor ("Wi-Fi"/"Ethernet"/…).
    func sample(connectionType: String) -> NetworkSnapshot?
}

/// Owns the previous byte counters and the `SCDynamicStore` handle used for
/// gateway/DNS lookups. Extracted verbatim from `MetricsEngine.updateNetwork`.
final class NetworkSampler: NetworkSampling {
    private var previousBytes: (received: UInt64, sent: UInt64)?
    private var previousTimestamp: Date?
    private let dynStore: SCDynamicStore? = SCDynamicStoreCreate(nil, "PerformanceApp" as CFString, nil, nil)

    func sample(connectionType: String) -> NetworkSnapshot? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var totalReceived: UInt64 = 0
        var totalSent: UInt64 = 0
        var interfaces: [LocalInterface] = []
        var vpnDetected = false
        let wifiIfaceName = CWWiFiClient.shared().interface()?.interfaceName

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let ifa = current.pointee
            let name = String(cString: ifa.ifa_name)
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), !name.hasPrefix("lo") {
                if let data = ifa.ifa_data {
                    let networkData = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
                    totalReceived += UInt64(networkData.ifi_ibytes)
                    totalSent += UInt64(networkData.ifi_obytes)
                }
            }
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), !name.hasPrefix("lo") {
                let addrIn = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var addr = addrIn.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: buffer)
                    let isVPN = name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec")
                    if isVPN { vpnDetected = true }
                    let kind: LocalInterface.Kind
                    if isVPN {
                        kind = .vpn
                    } else if name == wifiIfaceName {
                        kind = .wifi
                    } else if name.hasPrefix("en") || name.hasPrefix("bridge") {
                        kind = .ethernet
                    } else {
                        kind = .other
                    }
                    // Compute subnet prefix and network address from the netmask.
                    var prefix: Int? = nil
                    var netAddr: String? = nil
                    if let nm = ifa.ifa_netmask, nm.pointee.sa_family == UInt8(AF_INET) {
                        let maskBits = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                        }
                        prefix = maskBits.nonzeroBitCount
                        let net = UInt32(bigEndian: addrIn.sin_addr.s_addr) & maskBits
                        netAddr = "\(net >> 24).\((net >> 16) & 0xFF).\((net >> 8) & 0xFF).\(net & 0xFF)"
                    }
                    if !isVPN {
                        var gw: String? = nil
                        if let store = dynStore {
                            // Per-interface key (present when DHCP assigns the route)
                            if let dict = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(name)/IPv4" as CFString) as? [String: Any],
                               let router = dict["Router"] as? String, !router.contains(":") {
                                gw = router
                            }
                            // Fallback: global default gateway for the primary interface
                            if gw == nil,
                               let globalDict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
                               (globalDict["PrimaryInterface"] as? String) == name,
                               let router = globalDict["Router"] as? String, !router.contains(":") {
                                gw = router
                            }
                        }
                        interfaces.append(LocalInterface(name: name, address: ip, kind: kind,
                                                         prefixLength: prefix, networkAddress: netAddr,
                                                         gateway: gw))
                    }
                }
            }
            ptr = ifa.ifa_next
        }

        // Mark the primary interface and sort it to the top
        let primaryKind: LocalInterface.Kind = connectionType == "Wi-Fi" ? .wifi : .ethernet
        let sortedInterfaces = interfaces
            .map { iface in
                var i = iface; i.isPrimary = (i.kind == primaryKind); return i
            }
            .sorted { $0.isPrimary && !$1.isPrimary }

        var vpnIsFortiClient = false
        if vpnDetected {
            vpnIsFortiClient = NSWorkspace.shared.runningApplications.contains {
                let id = $0.bundleIdentifier?.lowercased() ?? ""
                let name = $0.localizedName?.lowercased() ?? ""
                return id.contains("fortinet") || id.contains("forticlient") || name.contains("forticlient")
            }
        }

        var downloadKBps: Double = 0
        var uploadKBps: Double = 0
        let now = Date()
        if let prev = previousBytes, let prevTime = previousTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let receivedDelta = Double(totalReceived &- prev.received)
                let sentDelta = Double(totalSent &- prev.sent)
                downloadKBps = max(receivedDelta, 0) / elapsed / 1024
                uploadKBps = max(sentDelta, 0) / elapsed / 1024
            }
        }
        previousBytes = (totalReceived, totalSent)
        previousTimestamp = now

        // Read active DNS servers from the system dynamic store.
        var dnsServers: [String] = []
        if let store = dynStore,
           let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let servers = dict["ServerAddresses"] as? [String] {
            dnsServers = servers.filter { !$0.contains(":") }
        }

        return NetworkSnapshot(downloadKBps: downloadKBps,
                               uploadKBps: uploadKBps,
                               interfaces: sortedInterfaces,
                               dnsServers: dnsServers,
                               isVPNActive: vpnDetected,
                               vpnIsFortiClient: vpnIsFortiClient)
    }
}
