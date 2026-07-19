import Testing
@testable import PerformanceAppCore

@Suite("LocalInterface")
struct LocalInterfaceTests {

    @Test func iconPerKind() {
        #expect(LocalInterface(name: "en0", address: "1.2.3.4", kind: .wifi).icon == "wifi")
        #expect(LocalInterface(name: "en1", address: "1.2.3.4", kind: .ethernet).icon == "cable.connector")
        #expect(LocalInterface(name: "utun0", address: "1.2.3.4", kind: .vpn).icon == "lock.shield.fill")
        #expect(LocalInterface(name: "awdl0", address: "1.2.3.4", kind: .other).icon == "network")
    }

    @Test func displayNamePerKind() {
        #expect(LocalInterface(name: "en0", address: "1.2.3.4", kind: .wifi).displayName == "Wi-Fi")
        #expect(LocalInterface(name: "en1", address: "1.2.3.4", kind: .ethernet).displayName == "Ethernet")
        #expect(LocalInterface(name: "utun0", address: "1.2.3.4", kind: .vpn).displayName == "VPN")
    }

    @Test func otherKindDisplayNameIsRawName() {
        // .other falls back to the raw interface name rather than a friendly label.
        #expect(LocalInterface(name: "bridge100", address: "1.2.3.4", kind: .other).displayName == "bridge100")
    }

    @Test func subnetMaskDerivesFromPrefixLength() {
        let iface = LocalInterface(name: "en0", address: "192.168.1.10", kind: .wifi, prefixLength: 24)
        #expect(iface.subnetMask == "255.255.255.0")
    }

    @Test func subnetMaskNilWhenPrefixMissing() {
        #expect(LocalInterface(name: "en0", address: "192.168.1.10", kind: .wifi).subnetMask == nil)
    }

    @Test func idIsInterfaceName() {
        #expect(LocalInterface(name: "en0", address: "1.2.3.4", kind: .wifi).id == "en0")
    }

    @Test func isPrimaryDefaultsFalseAndIsMutable() {
        var iface = LocalInterface(name: "en0", address: "1.2.3.4", kind: .wifi)
        #expect(iface.isPrimary == false)
        iface.isPrimary = true
        #expect(iface.isPrimary == true)
    }
}
