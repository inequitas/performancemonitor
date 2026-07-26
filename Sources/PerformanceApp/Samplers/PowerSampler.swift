import Foundation

protocol PowerSampling: AnyObject {
    /// Reads per-domain power off the main thread, throttled to once every 2s.
    /// Returns `nil` when IOReport is unavailable, the throttle blocks this
    /// call, or no baseline exists yet (the first sample only sets the baseline).
    func sample() async -> PowerSnapshot?

    /// Clears the 2s throttle so the next `sample` reads immediately. Used when
    /// a window that shows the values opens.
    func resetThrottle()
}

/// Owns the `PowerReader` handle and the 2s read throttle. `PowerReader` is
/// `@unchecked Sendable` and only ever touched from this sampler. Mirrors
/// `SMCSampler`.
@MainActor
final class PowerSampler: PowerSampling {
    private let reader = PowerReader()
    private var cacheDate: Date = .distantPast

    func resetThrottle() { cacheDate = .distantPast }

    func sample() async -> PowerSnapshot? {
        guard reader.isOpen else { return nil }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) > 2 else { return nil }
        cacheDate = now
        let reader = self.reader // capture before leaving @MainActor; PowerReader is @unchecked Sendable

        let snapshot = await Task.detached(priority: .utility) { () -> PowerSnapshot in
            reader.sample()
        }.value
        // A baseline-only first sample carries no values — don't publish it.
        return snapshot.hasAny ? snapshot : nil
    }
}
