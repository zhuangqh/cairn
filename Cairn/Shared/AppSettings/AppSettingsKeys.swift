import Foundation
import SwiftUI

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
