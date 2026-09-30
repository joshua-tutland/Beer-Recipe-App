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
    func start(_ key: String, step: BrewStep) {
        guard let minutes = step.durationMinutes else { return }
        var entry = entries[key] ?? Entry(
            timer: StepTimer(duration: minutes * 60),
            title: step.title,
            alerts: step.alerts.map { Alert(id: $0.id, secondsBeforeEnd: $0.minutesRemaining * 60, title: $0.title) })
        entry.timer.start(at: Date())
        entries[key] = entry
        requestAuthorizationIfNeeded()
        schedule(key, entry)
        save()
    }

    func pause(_ key: String) {
        guard let entry = entries[key] else { return }
        cancelNotifications(key, entry)
        entries[key]?.timer.pause(at: Date())
        save()
    }

    func reset(_ key: String) {
        guard let entry = entries[key] else { return }
        cancelNotifications(key, entry)
        entries[key] = nil
        save()
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
