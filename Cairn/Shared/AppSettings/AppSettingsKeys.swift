import Foundation
import SwiftUI

/// Namespaced `UserDefaults` keys and default values for app-level settings.
public enum AppSettingsKeys {
    public static let homeCurrency: String = "cairn.homeCurrency"
    public static let defaultHomeCurrency: String = "USD"

    public static let onboardingCompleted: String = "cairn.onboardingCompleted"

    /// Marks whether the user has seen the feature highlights tour. Flipped to
    /// `true` after the carousel is finished or skipped. Settings exposes a
    /// button that re-presents the tour without resetting any other state.
    public static let featureTourSeen: String = "cairn.featureTourSeen"

    public static let reminderEnabled: String = "cairn.reminderEnabled"
    public static let reminderHour: String = "cairn.reminderHour"     // 0-23
    public static let reminderMinute: String = "cairn.reminderMinute" // 0-59
    public static let reminderDay: String = "cairn.reminderDay"       // 1-28
    public static let defaultReminderHour: Int = 20
    public static let defaultReminderMinute: Int = 0
    public static let defaultReminderDay: Int = 1
    /// Upper bound for the monthly reminder day. Capped at 28 so the
    /// notification fires every month (including February).
    public static let reminderDayMax: Int = 28

    /// Stores the user's appearance preference. Values correspond to
    /// `AppAppearance.rawValue`.
    public static let appearance: String = "cairn.appearance"
}

/// User-facing appearance preference. `system` defers to the OS; `light` /
/// `dark` pin the app to a specific color scheme regardless of system
/// setting. Persisted as the raw string via `@AppStorage`.
public enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public static let `default`: AppAppearance = .system

    public var localizationKey: String {
        switch self {
        case .system: return "settings.appearance.system"
        case .light: return "settings.appearance.light"
        case .dark: return "settings.appearance.dark"
        }
    }

    /// Maps to the SwiftUI `preferredColorScheme` value. `nil` means
    /// "follow the system".
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
