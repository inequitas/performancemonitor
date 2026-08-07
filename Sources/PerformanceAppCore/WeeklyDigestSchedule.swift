import Foundation

/// Decides when the weekly summary notification is due.
///
/// The rule is "once on Monday morning", which sounds like a job for a repeating
/// calendar trigger until you consider a Mac that was asleep at nine on Monday,
/// or shut for a fortnight. A trigger either fires into nothing or fires a
/// backlog. Asking "is it due?" on a tick that already runs handles both: a
/// machine woken on Wednesday still gets the summary it missed, and gets it
/// once.
///
/// Pure, so the awkward cases can be tested without waiting a week.
public enum WeeklyDigestSchedule {

    /// Earliest hour it may be sent, so a machine started at 3am does not report
    /// last week before its owner is awake.
    public static let hour = 9

    /// Whether the summary should be sent now.
    ///
    /// - Parameters:
    ///   - now: Current time.
    ///   - lastSent: When it was last sent, or `nil` if never.
    ///   - calendar: Injected so the tests do not depend on the machine's own
    ///     locale, and because which day starts a week is a calendar question.
    /// - Returns: `true` at most once per week.
    public static func isDue(now: Date,
                             lastSent: Date?,
                             calendar: Calendar = .current) -> Bool {
        guard calendar.component(.hour, from: now) >= hour else { return false }

        // Monday of the week `now` falls in. Sending is keyed to this rather
        // than to "is today Monday", so a Mac that was off on Monday still
        // reports when it comes back, instead of skipping to the week after.
        guard let thisMonday = monday(of: now, calendar: calendar) else { return false }
        guard now >= thisMonday else { return false }

        guard let lastSent else { return true }
        // Already sent for this week if the last send was on or after its Monday.
        return lastSent < thisMonday
    }

    /// Start of the Monday in the same week as `date`.
    ///
    /// Deliberately not `calendar.firstWeekday`: in a good part of the world
    /// that is Sunday, and a summary of "last week" landing on a Sunday morning
    /// is not what "Monday morning" was asked for.
    static func monday(of date: Date, calendar: Calendar) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        // weekday: 1 = Sunday … 7 = Saturday, in the Gregorian calendar.
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay)
    }
}
