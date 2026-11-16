import SwiftUI

// MARK: - Auxiliary cards for BatchEntryView
//
// Extracted so the main view file stays within lint limits. Scoped
// internal so the primary file can reference these helpers directly.

extension BatchEntryView {
    // MARK: - Month

    /// Selected day, date picker, fill-from-last action, and FX rates.
    func monthCard(_ rows: [HoldingRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            monthHeader
                .padding(.bottom, 14)
            fillFromLastAction(hasBlankWithPrevious: hasBlankWithPrevious(rows: rows))
            ratesSection(rows: rows)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                monthSummary
                Spacer(minLength: 12)
                monthPicker
            }

            VStack(alignment: .leading, spacing: 12) {
                monthSummary
                monthPicker
            }
        }
    }

    private var monthSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("batch.monthCard.title")
                .font(.subheadline)
                .foregroundStyle(Color.ink2)
            Text(verbatim: periodMonth.formatted(.dateTime.year().month(.wide).locale(locale).inUTC))
                .font(.title.bold())
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
    }

    private var monthPicker: some View {
        DatePicker(
            "batch.month",
            selection: $periodMonth,
            displayedComponents: [.date]
        )
        // The day key is UTC midnight; pick it in UTC so it isn't shown as
        // the previous day west of UTC.
        .environment(\.timeZone, Snapshot.utcCalendar.timeZone)
        .labelsHidden()
        .font(.subheadline.weight(.medium))
        .controlSize(.small)
        .fixedSize()
        .disabled(isMonthLocked)
        .onChange(of: periodMonth) { _, newValue in
            let day = Snapshot.normalizeDay(newValue)
            if day != periodMonth { periodMonth = day }
        }
    }

    private func fillFromLastAction(hasBlankWithPrevious: Bool) -> some View {
        Button {
            fillFromLast()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.to.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 30, height: 30)
                    .background(Color.accentSoft, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text("batch.fillFromLast")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accent)
                    Text("batch.fillFromLast.hint")
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ink3)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: LedgerMetrics.rowHeight + 8, alignment: .leading)
        .overlay(alignment: .top) { LedgerHairline() }
        .contentShape(Rectangle())
        .disabled(!hasBlankWithPrevious)
        .opacity(hasBlankWithPrevious ? 1 : 0.52)
        .help(Text("batch.fillFromLast.hint"))
    }

    // MARK: - Rates

    /// Shows historical FX rates fetched for the selected month.
    /// Empty when all holdings are already in `homeCurrency`.
    @ViewBuilder
    func ratesSection(rows: [HoldingRow]) -> some View {
        let quotes = neededQuoteCurrencies(rows: rows)
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
                Text(verbatim: asOf.formatted(.dateTime.year().month().day().locale(locale).inUTC))
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
            // Rates are reference data, so they sit in a compact grid
            // rather than taking a full ledger row each.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(quotes, id: \.self) { quote in
                    rateCell(for: quote)
                }
            }
            .padding(.bottom, 14)
        }
    }

    /// `CNY → USD / 0.1400` — quote → home, the direction users value
    /// foreign holdings in.
    private func rateCell(for quote: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "1 \(quote) → \(homeCurrency)")
                .font(.caption)
                .foregroundStyle(Color.ink3)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
