import ActivityKit
import Foundation
import Observation
import UserNotifications
import BrewCore

/// Runs brew-day step timers and schedules local notifications for them, so alerts arrive
/// even when the phone is locked or the app is in the background.
///
/// Timers are keyed by session + step and saved to UserDefaults so they survive relaunches.
@Observable
final class BrewTimers {
    struct Entry: Codable {
        var timer: StepTimer
        var title: String
        var alerts: [Alert]
        /// Shown on the Lock Screen timer. Optional so timers saved by older versions still load.
        var recipeName: String?
    }

    struct Alert: Codable, Hashable {
        var id: String
        var secondsBeforeEnd: TimeInterval
        var title: String
    }

    private(set) var entries: [String: Entry] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    private static let storageKey = "brewTimers"

    init() {
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
    }

    static func key(session: UUID, step: String) -> String { "\(session.uuidString)/\(step)" }

    func timer(_ key: String, duration: TimeInterval) -> StepTimer {
        entries[key]?.timer ?? StepTimer(duration: duration)
    }

    /// Starts or resumes a step's timer.
    func start(_ key: String, step: BrewStep, recipeName: String = "") {
        guard let minutes = step.durationMinutes else { return }
        var entry = entries[key] ?? Entry(
            timer: StepTimer(duration: minutes * 60),
            title: step.title,
            alerts: step.alerts.map { Alert(id: $0.id, secondsBeforeEnd: $0.minutesRemaining * 60, title: $0.title) },
            recipeName: recipeName)
        entry.timer.start(at: Date())
        entries[key] = entry
        requestAuthorizationIfNeeded()
        schedule(key, entry)
        updateLiveActivity(key, entry)
        save()
    }

    func pause(_ key: String) {
        guard let entry = entries[key] else { return }
        cancelNotifications(key, entry)
        entries[key]?.timer.pause(at: Date())
        updateLiveActivity(key, entries[key])
        save()
    }

    func reset(_ key: String) {
        guard let entry = entries[key] else { return }
        cancelNotifications(key, entry)
        entries[key] = nil
        updateLiveActivity(key, nil)
        save()
    }

    // MARK: Lock Screen / Dynamic Island

    /// Starts, updates or ends the Live Activity for a timer. The countdown itself is drawn by
    /// iOS from the end date, so it keeps ticking without the app running.
    private func updateLiveActivity(_ key: String, _ entry: Entry?) {
        let existing = Activity<BrewTimerAttributes>.activities.first { $0.attributes.timerKey == key }
        guard let entry else {
            if let existing {
                Task { await existing.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let now = Date()
        let end = entry.timer.endDate
        let start = end.map { $0.addingTimeInterval(-entry.timer.duration) } ?? now
        let additions: [BrewTimerAttributes.Addition] = end.map { end in
            entry.alerts
                .map { BrewTimerAttributes.Addition(title: $0.title, date: end.addingTimeInterval(-$0.secondsBeforeEnd)) }
                .filter { $0.date > now }
                .sorted { $0.date < $1.date }
        } ?? []
        let state = BrewTimerAttributes.ContentState(stepTitle: entry.title, startDate: start, endDate: end,
                                                     pausedRemaining: entry.timer.pausedRemaining, additions: additions)
        let content = ActivityContent(state: state, staleDate: end?.addingTimeInterval(600))
        if let existing {
            Task { await existing.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = BrewTimerAttributes(recipeName: entry.recipeName ?? "Brew Day", timerKey: key)
            _ = try? Activity<BrewTimerAttributes>.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    /// Clears every timer belonging to a session (e.g. when it's deleted).
    func resetAll(session: UUID) {
        for key in entries.keys where key.hasPrefix(session.uuidString) { reset(key) }
    }

    // MARK: Notifications

    private func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [center] settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    private func schedule(_ key: String, _ entry: Entry) {
        cancelNotifications(key, entry)
        guard let end = entry.timer.endDate else { return }
        let now = Date()

        func add(_ id: String, at date: Date, title: String, body: String) {
            let interval = date.timeIntervalSince(now)
            guard interval > 0.5 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(key)|\(id)", content: content, trigger: trigger))
        }

        for alert in entry.alerts {
            add(alert.id, at: end.addingTimeInterval(-alert.secondsBeforeEnd),
                title: "Brew Day", body: alert.title)
        }
        add("end", at: end, title: "Timer Done", body: entry.title)
    }

    private func cancelNotifications(_ key: String, _ entry: Entry) {
        let ids = (entry.alerts.map(\.id) + ["end"]).map { "\(key)|\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// Shows brew-day notifications as banners even while the app is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
