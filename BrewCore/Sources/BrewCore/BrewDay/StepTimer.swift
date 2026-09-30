import Foundation

/// A countdown for a brew-day step. It stores an end date rather than ticking,
/// so it stays correct while the app is suspended or relaunched.
public struct StepTimer: Codable, Hashable, Sendable {
    public var duration: TimeInterval
    /// Set while running.
    public var endDate: Date?
    /// Set while paused.
    public var pausedRemaining: TimeInterval?

    public init(duration: TimeInterval) {
        self.duration = duration
    }

    public var isRunning: Bool { endDate != nil }
    public var isPaused: Bool { pausedRemaining != nil }
    public var isIdle: Bool { !isRunning && !isPaused }

    public func remaining(at now: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        if let pausedRemaining { return pausedRemaining }
        return duration
    }

    public func elapsed(at now: Date) -> TimeInterval { duration - remaining(at: now) }

    public func isFinished(at now: Date) -> Bool { isRunning && remaining(at: now) <= 0 }

    public func progress(at now: Date) -> Double {
        duration > 0 ? min(1, max(0, elapsed(at: now) / duration)) : 0
    }

    /// Starts, or resumes after a pause.
    public mutating func start(at now: Date) {
        endDate = now.addingTimeInterval(pausedRemaining ?? duration)
        pausedRemaining = nil
    }

    public mutating func pause(at now: Date) {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSince(now))
        self.endDate = nil
    }

    public mutating func reset() {
        endDate = nil
        pausedRemaining = nil
    }

    /// "1:05:09" or "59:09".
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
