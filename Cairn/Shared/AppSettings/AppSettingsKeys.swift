import Foundation

/// Namespaced `UserDefaults` keys and default values for app-level settings.
public enum AppSettingsKeys {
    public static let homeCurrency: String = "cairn.homeCurrency"
    public static let defaultHomeCurrency: String = "USD"

    public static let onboardingCompleted: String = "cairn.onboardingCompleted"

    public static let reminderEnabled: String = "cairn.reminderEnabled"
    public static let reminderHour: String = "cairn.reminderHour"     // 0-23
    public static let reminderMinute: String = "cairn.reminderMinute" // 0-59
    public static let defaultReminderHour: Int = 20
    public static let defaultReminderMinute: Int = 0
}
