import Testing
@testable import PerformanceAppCore

@Suite("ListeningPortList")
struct ListeningPortTests {

    private func socket(_ pid: Int32, _ name: String, _ port: UInt16, v6: Bool = false)
        -> ListeningPortList.Socket {
        ListeningPortList.Socket(pid: pid, processName: name, port: port, isIPv6: v6)
    }

    @Test func bothAddressFamiliesBecomeOneRow() {
        // Measured on a real machine: ControlCenter listed port 7000 twice and
        // rapportd port 64469 twice, once per family. Two identical-looking rows
        // invite the reader to wonder what the difference is when there is
        // nothing there worth their attention.
        let found = ListeningPortList.aggregate([
            socket(1, "ControlCenter", 7000),
            socket(1, "ControlCenter", 7000, v6: true),
        ])
        #expect(found.count == 1)
        #expect(found[0].bothFamilies)
    }

    @Test func oneFamilyIsMarkedAsSuch() {
        let found = ListeningPortList.aggregate([socket(1, "sshd", 22)])
        #expect(found.count == 1)
        #expect(!found[0].bothFamilies)
    }

    @Test func thesameportInTwoProcessesStaysTwoRows() {
        // Different processes on the same port number are genuinely different
        // things, however unusual that is.
        let found = ListeningPortList.aggregate([
            socket(1, "alpha", 8080),
            socket(2, "beta", 8080),
        ])
        #expect(found.count == 2)
    }

    @Test func oneProcessOnSeveralPortsKeepsThemApart() {
        let found = ListeningPortList.aggregate([
            socket(1, "LogiPluginService", 60955),
            socket(1, "LogiPluginService", 60957),
            socket(1, "LogiPluginService", 60960),
        ])
        #expect(found.count == 3)
    }

    @Test func sortedByPortThenName() {
        let found = ListeningPortList.aggregate([
            socket(1, "zulu", 8080),
            socket(2, "alpha", 22),
            socket(3, "bravo", 8080),
        ])
        #expect(found.map(\.port) == [22, 8080, 8080])
        #expect(found.map(\.processName) == ["alpha", "bravo", "zulu"])
    }

    @Test func nothingListeningIsNotAnError() {
        #expect(ListeningPortList.aggregate([]).isEmpty)
    }

    @Test func familiarPortsAreNamed() {
        #expect(ListeningPortList.wellKnownUse(22) == "SSH")
        #expect(ListeningPortList.wellKnownUse(5432) == "PostgreSQL")
        #expect(ListeningPortList.wellKnownUse(7000) == "AirPlay")
    }

    @Test func anUnknownPortIsNotGuessedAt() {
        // A port number does not prove what is behind it; the process name
        // beside it is what actually identifies the thing.
        #expect(ListeningPortList.wellKnownUse(60955) == nil)
    }
}
