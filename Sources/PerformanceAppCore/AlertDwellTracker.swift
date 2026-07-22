import Foundation

/// Tracks how long a metric has been *continuously* over its alert
/// threshold, so a caller can require a sustained ("dwell") duration before
/// firing an alert instead of reacting to a single momentary spike.
///
/// Timestamp-based rather than tick-counted: the refresh interval driving
/// `shouldFire` calls can vary (app backgrounded, slow tick, etc.), so
/// counting ticks would make the effective dwell duration depend on how
/// often the caller happens to poll. Wall-clock time does not.
///
/// One tracker instance can hold independent state for multiple metric keys
/// (e.g. "cpu", "gpu", "memory") simultaneously.
public struct AlertDwellTracker {
    private var sinceTimestamps: [String: Date] = [:]

    public init() {}

    /// - Parameters:
    ///   - key: identifies the metric this call concerns (e.g. "cpu").
    ///     Independent keys track independent dwell state.
    ///   - isOver: whether the metric is at/above its threshold *right now*.
    ///   - now: the current time, supplied by the caller so this type stays
    ///     pure and testable without a real clock.
    ///   - dwell: how long, in seconds, `isOver` must stay continuously true
    ///     before this returns `true`. `0` (or negative) means "fire
    ///     immediately," preserving the pre-dwell behaviour.
    /// - Returns: `true` once the value has been continuously over threshold
    ///   for at least `dwell` seconds; `false` otherwise. Any moment where
    ///   `isOver` is `false` resets the "since" timestamp for that key, so a
    ///   brief dip below threshold requires a fresh full dwell period.
    @discardableResult
    public mutating func shouldFire(key: String, isOver: Bool, now: Date, dwell: TimeInterval) -> Bool {
        guard isOver else {
            sinceTimestamps[key] = nil
            return false
        }
        guard dwell > 0 else {
            sinceTimestamps[key] = nil
            return true
        }
        let since = sinceTimestamps[key] ?? now
        sinceTimestamps[key] = since
        return now.timeIntervalSince(since) >= dwell
    }
}
