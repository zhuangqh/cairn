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
            LedgerSection(Text("batch.rates.title")) {
                ratesMeta
            } content: {
                ratesBody(quotes: quotes)
            }
        }
    }

    @ViewBuilder
    private var ratesMeta: some View {
        HStack(spacing: 6) {
            if isLoadingRates {
                ProgressView().controlSize(.mini)
            }
            if let asOf = historicalRatesAsOf {
                Text(asOf, format: .dateTime.year().month().day().locale(locale))
                    .monospacedDigit()
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.ink3)
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
            .foregroundStyle(Color.red)
            .padding(.bottom, 10)
        } else if historicalRates.isEmpty && !isLoadingRates {
            Text("batch.rates.empty")
                .font(.caption)
                .foregroundStyle(Color.ink2)
                .padding(.bottom, 10)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(quotes.enumerated()), id: \.element) { index, quote in
                    if index > 0 { LedgerHairline() }
                    rateRow(for: quote)
                }
            }
        }
    }

    /// `1 CNY → USD    0.1400` — quote → home, the direction users value
    /// foreign holdings in.
    private func rateRow(for quote: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "1 \(quote) → \(homeCurrency)")
                .font(.callout)
                .foregroundStyle(Color.ink2)
            Spacer(minLength: 8)
            if let inverted = inverseRate(for: quote) {
                Text(
                    inverted,
                    format: .number.precision(.fractionLength(4)).locale(locale)
                )
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(Color.ink)
            } else {
                Text(verbatim: "—")
                    .font(.callout)
                    .foregroundStyle(Color.ink3)
            }
        }
        .frame(minHeight: LedgerMetrics.rowHeight)
        .accessibilityElement(children: .combine)
    }

    /// Frankfurter returns `1 home == rate × quote`, so
    /// `1 quote == 1 / rate × home`. Returns `nil` for zero/missing rates.
    private func inverseRate(for quote: String) -> Decimal? {
        guard let rate = historicalRates[quote], rate != 0 else { return nil }
        return 1 / rate
    }

    // MARK: - Notes

    var notesCard: some View {
        LedgerSection(Text("batch.notes.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("batch.notes.hint")
                    .font(.footnote)
                    .foregroundStyle(Color.ink3)
                notesEditor
            }
            .padding(.bottom, 10)
        }
    }

    private var notesEditor: some View {
        TextEditor(text: $note)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120, maxHeight: 260)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if note.isEmpty {
                    Text("batch.notes.placeholder")
                        .font(.body)
                        .foregroundStyle(Color.placeholder)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }
}
