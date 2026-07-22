import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("PublicIPFetch")
struct PublicIPFetchTests {

    // MARK: - shouldFetch cadence

    @Test func noRefetchWithinFiveMinutesOfSuccess() {
        let now = Date()
        let lastSuccess = now.addingTimeInterval(-100)
        #expect(!PublicIPFetch.shouldFetch(lastSuccess: lastSuccess, lastFailure: nil, now: now,
                                            networkChanged: false, inFlight: false))
    }

    @Test func refetchAfterFiveMinutesSinceSuccess() {
        let now = Date()
        let lastSuccess = now.addingTimeInterval(-301)
        #expect(PublicIPFetch.shouldFetch(lastSuccess: lastSuccess, lastFailure: nil, now: now,
                                           networkChanged: false, inFlight: false))
    }

    @Test func firstEverFetchHasNoPriorState() {
        let now = Date()
        #expect(PublicIPFetch.shouldFetch(lastSuccess: nil, lastFailure: nil, now: now,
                                           networkChanged: false, inFlight: false))
    }

    // MARK: - failure -> fast retry, not the full 5 minutes

    @Test func failureRetriesQuicklyRatherThanWaitingFiveMinutes() {
        let now = Date()
        let lastFailure = now.addingTimeInterval(-20) // past the 15s backoff
        #expect(PublicIPFetch.shouldFetch(lastSuccess: nil, lastFailure: lastFailure, now: now,
                                           networkChanged: false, inFlight: false))
    }

    @Test func failureDoesNotHammerEveryTick() {
        let now = Date()
        let lastFailure = now.addingTimeInterval(-5) // still inside the backoff window
        #expect(!PublicIPFetch.shouldFetch(lastSuccess: nil, lastFailure: lastFailure, now: now,
                                            networkChanged: false, inFlight: false))
    }

    // MARK: - network change forces a refetch

    @Test func networkChangeForcesRefetchDespiteRecentSuccess() {
        let now = Date()
        let lastSuccess = now.addingTimeInterval(-5) // well inside the 5-minute window
        #expect(PublicIPFetch.shouldFetch(lastSuccess: lastSuccess, lastFailure: nil, now: now,
                                           networkChanged: true, inFlight: false))
    }

    @Test func networkChangeForcesRefetchDespiteRecentFailure() {
        let now = Date()
        let lastFailure = now.addingTimeInterval(-1) // well inside the backoff window
        #expect(PublicIPFetch.shouldFetch(lastSuccess: nil, lastFailure: lastFailure, now: now,
                                           networkChanged: true, inFlight: false))
    }

    // MARK: - in-flight guard always wins

    @Test func inFlightNeverAllowsAConcurrentFetch() {
        let now = Date()
        #expect(!PublicIPFetch.shouldFetch(lastSuccess: nil, lastFailure: nil, now: now,
                                            networkChanged: true, inFlight: true))
    }

    // MARK: - IP validation

    @Test func validIPv4IsPlausible() {
        #expect(PublicIPFetch.isPlausibleIPAddress("203.0.113.42"))
        #expect(PublicIPFetch.isPlausibleIPAddress("  8.8.8.8\n")) // trims whitespace/newlines
        #expect(PublicIPFetch.isPlausibleIPAddress("0.0.0.0"))
        #expect(PublicIPFetch.isPlausibleIPAddress("255.255.255.255"))
    }

    @Test func validIPv6IsPlausible() {
        #expect(PublicIPFetch.isPlausibleIPAddress("2001:db8:85a3::8a2e:370:7334"))
        #expect(PublicIPFetch.isPlausibleIPAddress("::1"))
        #expect(PublicIPFetch.isPlausibleIPAddress("fe80::1"))
    }

    @Test func emptyResponseIsNotPlausible() {
        #expect(!PublicIPFetch.isPlausibleIPAddress(""))
        #expect(!PublicIPFetch.isPlausibleIPAddress("   \n"))
    }

    @Test func nonIPTextIsNotPlausible() {
        #expect(!PublicIPFetch.isPlausibleIPAddress("<html><body>error</body></html>"))
        #expect(!PublicIPFetch.isPlausibleIPAddress("rate limit exceeded"))
        #expect(!PublicIPFetch.isPlausibleIPAddress("999.999.999.999"))
        #expect(!PublicIPFetch.isPlausibleIPAddress("1.2.3"))
        #expect(!PublicIPFetch.isPlausibleIPAddress("not.an.ip.addr"))
    }
}
