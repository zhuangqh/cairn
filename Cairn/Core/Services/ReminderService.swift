import Foundation
import UserNotifications

/// Local notification on the 1st of each month reminding the user to record
/// their snapshot. Single repeating notification (PRD F-SNAP-4).
public enum ReminderService {
    public static let identifier: String = "cairn.monthlyReminder"

    /// Requests notification permission if not already granted.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Schedules (or re-schedules) the monthly reminder at `hour:minute` local
    /// time, on day 1 of each month. Any previously scheduled Cairn reminder
    /// is removed first.
    public static func schedule(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "reminder.title")
        content.body = String(localized: "reminder.body")

        var components = DateComponents()
        components.day = 1
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
    public static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
