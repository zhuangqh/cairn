import SwiftUI

// MARK: - Auxiliary cards for BatchEntryView
//
// Extracted so the main view file stays within lint limits. Scoped
// internal so the primary file can reference these helpers directly.

extension BatchEntryView {
    /// Shows historical FX rates fetched for the selected month.
    /// Empty when all holdings are already in `homeCurrency`.
    @ViewBuilder
    var ratesSection: some View {
        let quotes = neededQuoteCurrencies
        if !quotes.isEmpty {
            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 8) {
                ratesHeader
                ratesBody(quotes: quotes)
            }
        }
    }

    @ViewBuilder
    private var ratesHeader: some View {
        HStack(spacing: 8) {
            Text("batch.rates.title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
            if isLoadingRates {
                ProgressView().controlSize(.mini)
            }
            Spacer()
            if let asOf = historicalRatesAsOf {
                Text(asOf, format: .dateTime.year().month().day().locale(locale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func ratesBody(quotes: [String]) -> some View {
        if let ratesFetchError {
            Label {
                Text(verbatim: ratesFetchError)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        } else if historicalRates.isEmpty && !isLoadingRates {
            Text("batch.rates.empty")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            rateChips(for: quotes)
        }
    }

    @ViewBuilder
    private func rateChips(for quotes: [String]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(quotes, id: \.self) { quote in
                rateChip(for: quote)
            }
        }
    }

    @ViewBuilder
    private func rateChip(for quote: String) -> some View {
        HStack(spacing: 6) {
            // Show quote -> home ("1 USD = ? CNY") — the direction users
            // actually think in when valuing foreign holdings.
            Text(verbatim: "1 \(quote) → \(homeCurrency)")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let inverted = inverseRate(for: quote) {
                Text(
                    inverted,
                    format: .number.precision(.fractionLength(2...4)).locale(locale)
                )
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.notionInk)
            } else {
                Text(verbatim: "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.notionSurfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.notionBorder, lineWidth: 1)
        )
    }

    /// Frankfurter returns `1 home == rate × quote`, so
    /// `1 quote == 1 / rate × home`. Returns `nil` for zero/missing rates.
    private func inverseRate(for quote: String) -> Decimal? {
        guard let rate = historicalRates[quote], rate != 0 else { return nil }
        return 1 / rate
    }

    // MARK: - Notes

    var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GlyphBadge(systemName: "note.text", tint: .accentColor, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("batch.notes.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Text("batch.notes.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            notesEditor
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 16)
    }

    private var notesEditor: some View {
        TextEditor(text: $note)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120, maxHeight: 260)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.notionSurfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.notionBorder, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if note.isEmpty {
                    Text("batch.notes.placeholder")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }
}
