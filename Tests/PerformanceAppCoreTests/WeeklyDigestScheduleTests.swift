import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("WeeklyDigestSchedule")
struct WeeklyDigestScheduleTests {

    /// Fixed calendar and zone, so none of this depends on where the tests run.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // 3 August 2026 is a Monday.
    private let monday = 3, tuesday = 4, wednesday = 5, sunday = 9

    @Test func mondayMorningIsDue() {
        #expect(WeeklyDigestSchedule.isDue(now: date(2026, 8, monday, 9),
                                           lastSent: nil, calendar: calendar))
    }

    @Test func tooEarlyOnMondayIsNot() {
        // A Mac started at 3am should not report last week before anyone is up.
        #expect(!WeeklyDigestSchedule.isDue(now: date(2026, 8, monday, 3),
                                            lastSent: nil, calendar: calendar))
    }

    @Test func onlyOncePerWeek() {
        let sent = date(2026, 8, monday, 9)
        #expect(!WeeklyDigestSchedule.isDue(now: date(2026, 8, monday, 10),
                                            lastSent: sent, calendar: calendar))
        #expect(!WeeklyDigestSchedule.isDue(now: date(2026, 8, wednesday, 12),
                                            lastSent: sent, calendar: calendar))
        #expect(!WeeklyDigestSchedule.isDue(now: date(2026, 8, sunday, 20),
                                            lastSent: sent, calendar: calendar))
    }

    @Test func theWeekAfterIsDueAgain() {
        #expect(WeeklyDigestSchedule.isDue(now: date(2026, 8, 10, 9),
                                           lastSent: date(2026, 8, monday, 9),
                                           calendar: calendar))
    }

    @Test func aMacThatWasOffOnMondayStillGetsIt() {
        // The whole reason this is a question asked on a tick rather than a
        // repeating calendar trigger: a trigger fires into nothing.
        #expect(WeeklyDigestSchedule.isDue(now: date(2026, 8, wednesday, 14),
                                           lastSent: nil, calendar: calendar))
    }

    @Test func aMacBackFromAFortnightGetsOneSummaryNotTwo() {
        let due = WeeklyDigestSchedule.isDue(now: date(2026, 8, tuesday, 10),
                                             lastSent: date(2026, 7, 20, 9),
                                             calendar: calendar)
        #expect(due)
        // And having sent it, the same week does not fire again.
        #expect(!WeeklyDigestSchedule.isDue(now: date(2026, 8, wednesday, 10),
                                            lastSent: date(2026, 8, tuesday, 10),
                                            calendar: calendar))
    }

    @Test func sundayBelongsToTheWeekThatStartedOnMonday() {
        // Not calendar.firstWeekday, which is Sunday in much of the world: a
        // summary landing on Sunday morning is not "Monday morning".
        let sundayMonday = WeeklyDigestSchedule.monday(of: date(2026, 8, sunday, 12), calendar: calendar)
        #expect(sundayMonday == date(2026, 8, monday))
    }

    @Test func mondayIsItsOwnWeekStart() {
        let start = WeeklyDigestSchedule.monday(of: date(2026, 8, monday, 23), calendar: calendar)
        #expect(start == date(2026, 8, monday))
    }
}
