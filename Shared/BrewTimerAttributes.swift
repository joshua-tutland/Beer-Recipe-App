import ActivityKit
import Foundation

/// What a brew-day timer shows on the Lock Screen and in the Dynamic Island.
/// Compiled into both the app and the BrewTimerWidget extension.
struct BrewTimerAttributes: ActivityAttributes {
    struct Addition: Codable, Hashable {
        var title: String
        var date: Date
    }

    struct ContentState: Codable, Hashable {
        var stepTitle: String
        var startDate: Date
        /// Set while running.
        var endDate: Date?
        /// Set while paused.
        var pausedRemaining: TimeInterval?
        /// Upcoming additions (e.g. hop additions during the boil) with their clock times.
        var additions: [Addition]
    }

    var recipeName: String
    /// Identifies the timer inside the app (session + step), so the activity can be found again.
    var timerKey: String
}
