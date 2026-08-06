import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("PMSetLogParser")
struct PMSetLogParserTests {

    // Lines copied from real `pmset -g log` output, tabs and all.
    private let sample = """
    2026-08-06 08:06:01 +0200 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:22%) 32 secs
    2026-08-06 08:06:33 +0200 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:22%) 116 secs
    2026-08-06 08:08:29 +0200 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty RTP.multi-touch/HID Activity Using BATT (Charge:22%)
    2026-08-06 08:08:29 +0200 WakeDetails         \tDriverReason:smc.sysState.Wake(0x70070000) - DriverDetails:
    2026-08-06 08:08:29 +0200 WakeTime            \tWakeTime: 0.219 sec
    """

    @Test func sleepAndWakeAreFound() {
        let events = PMSetLogParser.parse(sample)
        #expect(events.count == 2)
        #expect(events.contains { $0.kind == .sleep })
        #expect(events.contains { if case .wake = $0.kind { return true }; return false })
    }

    @Test func darkWakeIsSkipped() {
        // macOS wakes itself for maintenance several times an hour and nobody
        // sees it happen. On the machine this was written against there were
        // 726 of those against 808 real wakes; drawn on a graph they would bury
        // the events someone might actually recognise.
        let events = PMSetLogParser.parse(sample)
        #expect(!events.contains { $0.date == Date(timeIntervalSince1970: 0) })
        #expect(events.count == 2)
    }

    @Test func companionLinesAreNotMistakenForEvents() {
        // WakeDetails and WakeTime share the timestamp of the wake they belong
        // to, and a looser prefix test would count the same wake three times.
        #expect(PMSetLogParser.parse(sample).count == 2)
    }

    @Test func timestampsAreReadWithTheirOffset() {
        let events = PMSetLogParser.parse(sample)
        let sleep = events.first { $0.kind == .sleep }
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 6
        components.hour = 8; components.minute = 6; components.second = 33
        components.timeZone = TimeZone(secondsFromGMT: 2 * 3600)
        #expect(sleep?.date == Calendar(identifier: .gregorian).date(from: components))
    }

    @Test func newestComesFirst() {
        let events = PMSetLogParser.parse(sample)
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.date >= $1.date })
    }

    @Test func theListIsTrimmed() {
        // A machine that has been alive for years has thousands of these, and
        // only the recent ones can line up with the history that is kept.
        let many = (0..<50).map { i in
            "2026-08-0\(i % 9 + 1) 08:06:33 +0200 Sleep               \tEntering Sleep state"
        }.joined(separator: "\n")
        #expect(PMSetLogParser.parse(many, limit: 10).count == 10)
    }

    @Test func emptyOutputYieldsNothing() {
        #expect(PMSetLogParser.parse("").isEmpty)
    }

    @Test func garbageIsSkippedRatherThanGuessedAt() {
        #expect(PMSetLogParser.parse("not a log line at all\n\n   ").isEmpty)
    }

    @Test func aLineWithAnUnreadableDateIsDropped() {
        #expect(PMSetLogParser.parse("yesterday afternoon ish +0200 Sleep  Entering Sleep").isEmpty)
    }

    // MARK: - Wake reasons

    @Test func theLidIsRecognised() {
        #expect(PMSetLogParser.wakeReason(in: "due to smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty") == .lid)
    }

    @Test func touchingTheMachineIsRecognised() {
        #expect(PMSetLogParser.wakeReason(in: "RTP.multi-touch/HID Activity") == .keyboard)
    }

    @Test func aScheduledWakeIsRecognised() {
        #expect(PMSetLogParser.wakeReason(in: "due to EC.RTC") == .scheduled)
        #expect(PMSetLogParser.wakeReason(in: "'Maintenance Sleep'") == .scheduled)
    }

    @Test func anUnreadableReasonSaysSoRatherThanGuessing() {
        // Better to show no reason than to translate a driver code into a story.
        #expect(PMSetLogParser.wakeReason(in: "due to smc.sysState.Wake(0x70070000)") == .unknown)
    }
}
