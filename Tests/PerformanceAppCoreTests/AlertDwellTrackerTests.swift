import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("AlertDwellTracker")
struct AlertDwellTrackerTests {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    @Test func dwellZeroFiresImmediately() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: 0) == true)
    }

    @Test func belowDwellDurationDoesNotFire() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(10), dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(29.9), dwell: 30) == false)
    }

    @Test func exactlyAtDwellDurationFires() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(30), dwell: 30) == true)
    }

    @Test func pastDwellDurationKeepsFiring() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(45), dwell: 30) == true)
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(300), dwell: 30) == true)
    }

    @Test func dippingBelowThresholdResetsTheClock() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(25), dwell: 30) == false)
        // Brief dip below threshold — resets the "since" timestamp.
        #expect(tracker.shouldFire(key: "cpu", isOver: false, now: base.addingTimeInterval(26), dwell: 30) == false)
        // Back over threshold, but only 4s after the reset — must not fire yet
        // even though 30s have passed since the original excursion started.
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(30), dwell: 30) == false)
        // A fresh full dwell period after the reset (from t=30) does fire.
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(60), dwell: 30) == true)
    }

    @Test func momentarySpikeNeverFires() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: false, now: base.addingTimeInterval(1), dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: false, now: base.addingTimeInterval(2), dwell: 30) == false)
    }

    @Test func multipleKeysTrackIndependently() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: 30) == false)
        // GPU starts its excursion later — must not inherit CPU's clock.
        #expect(tracker.shouldFire(key: "gpu", isOver: true, now: base.addingTimeInterval(20), dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(31), dwell: 30) == true)
        #expect(tracker.shouldFire(key: "gpu", isOver: true, now: base.addingTimeInterval(31), dwell: 30) == false)
        #expect(tracker.shouldFire(key: "gpu", isOver: true, now: base.addingTimeInterval(51), dwell: 30) == true)
    }

    @Test func variableTimeIntervalsBetweenCallsStillAccumulateCorrectly() {
        var tracker = AlertDwellTracker()
        // Irregular tick spacing (e.g. app briefly stalled) must still sum
        // to wall-clock elapsed time, not "number of calls".
        #expect(tracker.shouldFire(key: "mem", isOver: true, now: base, dwell: 60) == false)
        #expect(tracker.shouldFire(key: "mem", isOver: true, now: base.addingTimeInterval(1), dwell: 60) == false)
        #expect(tracker.shouldFire(key: "mem", isOver: true, now: base.addingTimeInterval(3), dwell: 60) == false)
        #expect(tracker.shouldFire(key: "mem", isOver: true, now: base.addingTimeInterval(59), dwell: 60) == false)
        #expect(tracker.shouldFire(key: "mem", isOver: true, now: base.addingTimeInterval(61), dwell: 60) == true)
    }

    @Test func switchingDwellKeepsOriginalStartTimestamp() {
        // Changing the user's configured dwell mid-excursion should apply
        // to the existing "since" timestamp, not restart it.
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: 60) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base.addingTimeInterval(35), dwell: 30) == true)
    }

    @Test func negativeDwellBehavesLikeZero() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: true, now: base, dwell: -5) == true)
    }

    @Test func neverOverNeverFires() {
        var tracker = AlertDwellTracker()
        #expect(tracker.shouldFire(key: "cpu", isOver: false, now: base, dwell: 30) == false)
        #expect(tracker.shouldFire(key: "cpu", isOver: false, now: base.addingTimeInterval(1000), dwell: 30) == false)
    }
}
