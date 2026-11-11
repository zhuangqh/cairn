import SwiftUI

#if os(macOS)
/// macOS bottom bar for `BatchEntryView`: running total plus Cancel / Save.
struct BatchEntryMacFooter: View {
    @Environment(\.locale) private var locale

    let totalInHome: Decimal
    let homeCurrency: String
    let hasUnsavedEdits: Bool
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            footerSummary

            Spacer(minLength: 24)

            Button {
                onCancel()
            } label: {
                Text("common.action.cancel")
            }
            .keyboardShortcut(.cancelAction)

            saveButton
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
        .background(Color.notionSurfaceAlt)
        .overlay(alignment: .top) { Divider().opacity(0.55) }
    }

    private var footerSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("batch.total")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ink2)
                .textCase(.uppercase)
            Text(
                totalInHome,
                format: .currency(code: homeCurrency)
                    .precision(.fractionLength(0))
                    .locale(locale)
            )
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.ink)
        }
    }

    private var saveButton: some View {
        Button {
            onSave()
        } label: {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 72)
            } else {
                Label("batch.save", systemImage: "checkmark")
            }
        }
        .controlSize(.large)
        .disabled(!hasUnsavedEdits || isSaving)
        .buttonStyle(.borderedProminent)
    }
}
#else
/// Floating glass total for `BatchEntryView` on iPhone and iPad, with a
/// warning when some entered currencies have no rate.
struct BatchEntryFloatingTotal: View {
    @Environment(\.locale) private var locale

    let totalInHome: Decimal
    let homeCurrency: String
    let unresolvedCurrencies: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("batch.total")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ink3)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer(minLength: 8)

                Text(
                    totalInHome,
                    format: .currency(code: homeCurrency)
                        .precision(.fractionLength(0))
                        .locale(locale)
                )
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            if !unresolvedCurrencies.isEmpty {
                Label {
                    Text(MissingRatesMessage.text(for: unresolvedCurrencies))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .liquidGlassBackground(cornerRadius: 16, tint: Color.accent.opacity(0.018))
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
#endif
