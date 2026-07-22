import Testing
@testable import PerformanceAppCore

@Suite("NetworkInterfaceFilter")
struct NetworkInterfaceFilterTests {

    @Test func physicalEthernetAndWiFiInterfacesAreIncluded() {
        #expect(NetworkInterfaceFilter.isPhysical("en0"))
        #expect(NetworkInterfaceFilter.isPhysical("en1"))
        #expect(NetworkInterfaceFilter.isPhysical("en10"))
    }

    @Test func vpnAndTunnelInterfacesAreExcluded() {
        #expect(!NetworkInterfaceFilter.isPhysical("utun0"))
        #expect(!NetworkInterfaceFilter.isPhysical("utun9"))
        #expect(!NetworkInterfaceFilter.isPhysical("ppp0"))
        #expect(!NetworkInterfaceFilter.isPhysical("ipsec0"))
        #expect(!NetworkInterfaceFilter.isPhysical("gif0"))
        #expect(!NetworkInterfaceFilter.isPhysical("stf0"))
    }

    @Test func loopbackIsExcluded() {
        #expect(!NetworkInterfaceFilter.isPhysical("lo0"))
    }

    @Test func airdropAndPeerToPeerInterfacesAreExcluded() {
        #expect(!NetworkInterfaceFilter.isPhysical("awdl0"))
        #expect(!NetworkInterfaceFilter.isPhysical("llw0"))
        #expect(!NetworkInterfaceFilter.isPhysical("p2p0"))
    }

    @Test func bridgeInterfacesAreExcluded() {
        #expect(!NetworkInterfaceFilter.isPhysical("bridge0"))
        #expect(!NetworkInterfaceFilter.isPhysical("bridge100"))
    }
}
