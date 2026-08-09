import SwiftUI

enum AchievementFormatting {
    static func amount(_ presentation: AchievementPresentation, locale: Locale) -> String? {
        guard let amount = presentation.observedAmount,
              let currency = presentation.currencyCode
        else { return nil }
        return amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(0))
                .locale(locale)
        )
    }

    static func month(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.year().month(.wide).locale(locale))
    }

}
