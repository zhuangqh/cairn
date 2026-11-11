import Foundation
import UserNotifications

/// Local notification on the 1st of each month reminding the user to record
/// their snapshot. Single repeating notification (PRD F-SNAP-4).
enum ReminderService {
    static let identifier: String = "cairn.monthlyReminder"

    /// Requests notification permission if not already granted.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Schedules (or re-schedules) the monthly reminder at `hour:minute` local
    /// time, on the given `day` of each month. `day` is clamped to 1...28 so
    /// the reminder fires reliably every month (including February). Any
    /// previously scheduled Cairn reminder is removed first. `bundle` is the
    /// language bundle from `LocalizationService` for the notification text.
    static func schedule(day: Int, hour: Int, minute: Int, bundle: Bundle) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "reminder.title", bundle: bundle)
        content.body = String(localized: "reminder.body", bundle: bundle)

        var components = DateComponents()
        components.day = max(1, min(28, day))
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    /// Cancels the monthly reminder, if any.
    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
