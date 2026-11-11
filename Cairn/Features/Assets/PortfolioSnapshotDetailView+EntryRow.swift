import SwiftUI

extension PortfolioSnapshotDetailView {
    /// One captured holding: native-currency amount box with its delta.
    /// macOS reveals the home-currency conversion on hover; other
    /// platforms toggle it by tapping the amount. The hovered / converted
    /// entry IDs stay owned by the detail view so only one row at a time
    /// shows its conversion.
    struct EntryRowView: View {
        @Environment(\.locale) private var locale

        let row: EntryRow
        let homeCurrency: String
        @Binding var hoveredEntryID: UUID?
        @Binding var convertedEntryID: UUID?

        var body: some View {
            #if os(macOS)
            desktopEntryRow
            #else
            compactEntryRow
            #endif
        }

        private var compactEntryRow: some View {
            let entry = row.current
            let displaysConversion = convertedEntryID == entry.id && hasForeignConversion(entry)
            let displayedDelta = displaysConversion ? convertedDelta : row.delta
            let deltaCurrency = displaysConversion ? homeCurrency : entry.currency
            return VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .center, spacing: Metrics.rowSpacing) {
                    entryIdentity

                    Spacer(minLength: Metrics.minimumColumnSpacing)

                    if hasForeignConversion(entry) {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                convertedEntryID = displaysConversion ? nil : entry.id
                            }
                        } label: {
                            entryAmount(
                                entry,
                                displayInHomeCurrency: displaysConversion,
                                showsConversionAffordance: true
                            )
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                    } else {
                        entryAmount(entry)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if let displayedDelta {
                    HStack {
                        Spacer(minLength: Metrics.rowGlyphSize + Metrics.rowSpacing)
                        InlineDelta(amount: displayedDelta, currency: deltaCurrency)
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding(.vertical, Metrics.rowVerticalPadding)
            .animation(.easeOut(duration: 0.18), value: displaysConversion)
        }

        private var desktopEntryRow: some View {
            let entry = row.current
            let revealsConversion = hoveredEntryID == entry.id
            return HStack(alignment: .center, spacing: Metrics.rowSpacing) {
                entryIdentity

                Spacer(minLength: Metrics.minimumColumnSpacing)

                VStack(alignment: .trailing, spacing: 3) {
                    entryAmount(entry)
                    if let entryDelta = row.delta {
                        InlineDelta(amount: entryDelta, currency: entry.currency)
                    }
                    if let converted = entry.convertedAmount,
                       hasForeignConversion(entry), revealsConversion {
                        convertedAmountLabel(converted)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .layoutPriority(0)
            }
            .padding(.vertical, Metrics.rowVerticalPadding)
            .contentShape(Rectangle())
            .onHover { isHovering in
                updateHoveredEntry(entry.id, isHovering: isHovering)
            }
            .animation(.easeOut(duration: 0.18), value: revealsConversion)
        }

        private var entryIdentity: some View {
            let entry = row.current
            return HStack(alignment: .center, spacing: Metrics.rowSpacing) {
                GlyphBadge(
                    systemName: row.accountKind.iconName,
                    tint: row.accountKind.tint,
                    size: Metrics.rowGlyphSize
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: entry.accountName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.82)
                    if let label = entry.holdingLabel, !label.isEmpty {
                        Text(verbatim: label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)
            }
        }

        private func hasForeignConversion(_ entry: PortfolioSnapshot.Entry) -> Bool {
            entry.convertedAmount != nil && entry.currency != homeCurrency
        }

        private var convertedDelta: Decimal? {
            guard let current = row.current.convertedAmount,
                  let prior = row.prior?.convertedAmount else { return nil }
            return current - prior
        }

        private func updateHoveredEntry(_ entryID: UUID, isHovering: Bool) {
            if isHovering {
                hoveredEntryID = entryID
            } else if hoveredEntryID == entryID {
                hoveredEntryID = nil
            }
        }

        private func convertedAmountLabel(_ converted: Decimal) -> some View {
            Text(
                verbatim: "≈ " + converted.formatted(
                    .currency(code: homeCurrency)
                        .precision(.fractionLength(0))
                        .locale(locale)
                )
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }

        private func entryAmount(
            _ entry: PortfolioSnapshot.Entry,
            displayInHomeCurrency: Bool = false,
            showsConversionAffordance: Bool = false
        ) -> some View {
            let usesHomeCurrency = displayInHomeCurrency && entry.convertedAmount != nil
            let currency = usesHomeCurrency ? homeCurrency : entry.currency
            let amount = usesHomeCurrency ? (entry.convertedAmount ?? entry.amount) : entry.amount
            return HStack(spacing: 6) {
                Text(verbatim: currency)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(Color.ink3)

                if showsConversionAffordance {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.ink3.opacity(0.8))
                } else {
                    Divider()
                        .frame(height: 17)
                }

                Text(
                    amount,
                    format: .number
                        .precision(.fractionLength(0))
                        .locale(locale)
                )
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())
            }
            .padding(.horizontal, 9)
            .frame(width: Metrics.amountBoxWidth, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.notionSurfaceAlt.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 0.75)
            )
        }
    }
}
