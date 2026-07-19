import Foundation

/// A single local network interface (IPv4) with its addressing details.
///
/// Pure value type — no AppKit/SwiftUI dependencies. `icon` returns SF Symbol
/// names as plain strings so this can live in Core and be unit tested without
/// SwiftUI. Extracted from `MetricsEngine` in the Part-A decomposition.
public struct LocalInterface: Identifiable {
    public enum Kind { case wifi, ethernet, vpn, other }

    public let name: String
    public let address: String
    public let kind: Kind
    public var isPrimary: Bool
    public var prefixLength: Int?
    public var networkAddress: String?
    public var gateway: String?

    public init(name: String,
                address: String,
                kind: Kind,
                isPrimary: Bool = false,
                prefixLength: Int? = nil,
                networkAddress: String? = nil,
                gateway: String? = nil) {
        self.name = name
        self.address = address
        self.kind = kind
        self.isPrimary = isPrimary
        self.prefixLength = prefixLength
        self.networkAddress = networkAddress
        self.gateway = gateway
    }

    public var subnetMask: String? {
        SubnetMask.string(forPrefixLength: prefixLength)
    }

    public var id: String { name }

    public var icon: String {
        switch kind {
        case .wifi:     return "wifi"
        case .ethernet: return "cable.connector"
        case .vpn:      return "lock.shield.fill"
        case .other:    return "network"
        }
    }

    public var displayName: String {
        switch kind {
        case .wifi:     return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .vpn:      return "VPN"
        case .other:    return name
        }
    }
}
