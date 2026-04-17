import Foundation
import SwiftUI

/// Resolves which language the app is running in, honoring the user's override.
///
/// The app ships `en` and `zh-Hans` at v1 (see PRD §5.5). When the override equals
/// `.followSystem`, SwiftUI picks the best match from the system settings.
@Observable
public final class LocalizationService {
    public enum LanguageOverride: String, CaseIterable, Sendable {
        case followSystem
        case english
        case simplifiedChinese

        public var bcp47Code: String? {
            switch self {
            case .followSystem: return nil
            case .english: return "en"
            case .simplifiedChinese: return "zh-Hans"
            }
        }

        public var localizationKey: String {
            switch self {
            case .followSystem: return "settings.language.followSystem"
            case .english: return "settings.language.english"
            case .simplifiedChinese: return "settings.language.simplifiedChinese"
            }
        }
    }

    private static let overrideKey = "cairn.languageOverride"

    public var override: LanguageOverride {
        didSet {
            UserDefaults.standard.set(override.rawValue, forKey: Self.overrideKey)
        }
    }

    public init() {
        if let raw = UserDefaults.standard.string(forKey: Self.overrideKey),
           let value = LanguageOverride(rawValue: raw) {
            self.override = value
        } else {
            self.override = .followSystem
        }
    }

    /// Locale to apply to the SwiftUI environment. `nil` means "use system".
    public var effectiveLocale: Locale? {
        guard let code = override.bcp47Code else { return nil }
        return Locale(identifier: code)
    }
}
