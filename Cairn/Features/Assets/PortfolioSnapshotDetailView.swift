import SwiftUI
import SwiftData

/// Read-only **comparison view** for a captured `PortfolioSnapshot`.
///
/// The page is centred around explaining *change* against the prior
/// snapshot rather than just listing current values:
/// - Header: total + signed delta vs `previous`.
/// - Holdings: grouped by member, each member shows its own delta;
///   each row mirrors the snapshot editor's native-currency amount box
///   with the home-currency conversion on a secondary line.
/// - Change breakdown: market movement, FX impact, and manual updates
///   (added / removed holdings) — derived purely from the two snapshots.
struct PortfolioSnapshotDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query private var members: [Member]

    let snapshot: PortfolioSnapshot
    /// Optional explicit previous snapshot. When `nil`, the view looks
    /// up the chronologically prior snapshot from the database itself
    /// so deltas / change breakdown work regardless of any UI filter
    /// (year selector etc.) on the caller side.
    private let explicitPrevious: PortfolioSnapshot?

    @State private var showDeleteConfirm: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var errorMessage: String?
    @State private var resolvedPrevious: PortfolioSnapshot?
    @State private var resolvedCapturedDate: Date?
    @State private var hoveredEntryID: UUID?
    @State private var convertedEntryID: UUID?

    init(snapshot: PortfolioSnapshot, previous: PortfolioSnapshot? = nil) {
        self.snapshot = snapshot
        self.explicitPrevious = previous
    }

    /// Effective previous snapshot used by the comparison logic.
    private var previous: PortfolioSnapshot? {
        explicitPrevious ?? resolvedPrevious
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                if !snapshot.entries.isEmpty {
                    holdingsCard
                }
                if let breakdown, breakdown.hasContent {
                    changeBreakdownCard(breakdown)
                }
            }
            .padding(.horizontal, pageHorizontalInset)
            .padding(.vertical, 20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground()
        .navigationTitle(titleText)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            resolvePreviousIfNeeded()
            resolveCapturedDateIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(Text("common.action.edit"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            BatchEntryView(
                initialPeriodMonth: capturedDate,
                lockedRates: lockedRatesForEdit,
                lockedBaseline: lockedBaselineForEdit,
                initialNote: snapshot.note ?? ""
            )
        }
        .alert(
            "portfolioSnapshot.delete.confirm.title",
            isPresented: $showDeleteConfirm
        ) {
            Button(role: .destructive) {
                delete()
            } label: {
                Text("portfolioSnapshot.delete.confirm.action")
            }
            Button(role: .cancel) {} label: { Text("common.action.cancel") }
        } message: {
            Text("portfolioSnapshot.delete.confirm.message")
        }
        .alert(
            "portfolioSnapshot.delete.failure",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button { errorMessage = nil } label: { Text("common.action.done") }
        } message: {
            if let errorMessage { Text(verbatim: errorMessage) }
        }
    }

    private var titleText: String {
        snapshot.periodMonth.formatted(.dateTime.year().month(.wide).locale(locale))
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("portfolioSnapshot.detail.total")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: snapshot.homeCurrency)
                    .font(.caption.monospaced().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            Text(
                snapshot.totalAmount,
                format: .currency(code: snapshot.homeCurrency)
                    .precision(.fractionLength(0))
                    .locale(locale)
            )
                .font(.system(size: 36, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.notionInk)
            if let totalDelta {
                headerDeltaLine(totalDelta)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(
                    "portfolioSnapshot.detail.batchDate \(capturedDate, format: footnoteDateFormat)"
                ))
                Text(LocalizedStringKey(
                    "portfolioSnapshot.detail.capturedAt \(snapshot.recordedAt, format: footnoteDateFormat)"
                ))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let note = snapshot.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: detailCardCornerRadius, padding: detailCardPadding)
    }

    @ViewBuilder
    private func headerDeltaLine(_ delta: TotalDelta) -> some View {
        let isPositive = delta.amount >= 0
        let tint: Color = isPositive ? .notionGreen : .notionOrange
        HStack(spacing: 8) {
            Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
            Text(verbatim: signedAmount(delta.amount, currency: snapshot.homeCurrency))
                .font(.headline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
            if let percent = delta.percent {
                Text(verbatim: "(\(signedPercent(percent)))")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(tint.opacity(0.85))
            }
            Text(verbatim: vsPreviousLabel(delta.previousMonth))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Holdings

    @ViewBuilder
    private var holdingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailSectionTitle("portfolioSnapshot.detail.breakdown")
            #if os(macOS)
            memberCardsGrid
            #else
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(memberGroups.enumerated()), id: \.element.member) { index, group in
                    memberGroupCard(group)
                    if index < memberGroups.count - 1 {
                        Divider()
                            .opacity(0.45)
                            .padding(.vertical, 12)
                    }
                }
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: detailCardCornerRadius, padding: detailCardPadding)
    }

    #if os(macOS)
    private var memberCardsGrid: some View {
        let groups = memberGroups
        let pairs: [[MemberGroup]] = stride(from: 0, to: groups.count, by: 2).map { start in
            Array(groups[start..<min(start + 2, groups.count)])
        }
        return VStack(spacing: 12) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(pair, id: \.member) { group in
                        memberGroupCard(group)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                    if pair.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    #endif

    private func memberGroupCard(_ group: MemberGroup) -> some View {
        #if os(macOS)
        memberGroupSection(group)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Color.notionSurfaceAlt.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.notionBorder.opacity(0.65), lineWidth: 0.7)
            )
        #else
        memberGroupSection(group)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    @ViewBuilder
    private func memberGroupSection(_ group: MemberGroup) -> some View {
        let displayName = group.member.isEmpty
            ? String(localized: "portfolioSnapshot.detail.member.unassigned")
            : group.member
        let resolvedMember = group.member.isEmpty ? nil : memberByName[group.member]
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    MemberAvatarView(
                        name: displayName,
                        avatarData: resolvedMember?.avatarData,
                        seed: resolvedMember?.id ?? Self.unassignedMemberSeed,
                        size: memberAvatarSize
                    )
                    Text(verbatim: displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.notionInk)
                    Spacer(minLength: 8)
                    Text(
                        group.total,
                        format: .currency(code: snapshot.homeCurrency)
                            .precision(.fractionLength(0))
                            .locale(locale)
                    )
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.notionInkSecondary)
                }
                if let memberDelta = group.delta {
                    HStack {
                        Spacer(minLength: 0)
                        inlineDelta(memberDelta, currency: snapshot.homeCurrency)
                    }
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.current.id) { index, row in
                    entryRow(row)
                    if index < group.entries.count - 1 {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ row: EntryRow) -> some View {
        #if os(macOS)
        desktopEntryRow(row)
        #else
        compactEntryRow(row)
        #endif
    }

    private func compactEntryRow(_ row: EntryRow) -> some View {
        let entry = row.current
        let displaysConversion = convertedEntryID == entry.id && hasForeignConversion(entry)
        let displayedDelta = displaysConversion ? convertedDelta(for: row) : row.delta
        let deltaCurrency = displaysConversion ? snapshot.homeCurrency : entry.currency
        return VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .center, spacing: rowSpacing) {
                entryIdentity(row)

                Spacer(minLength: minimumColumnSpacing)

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
                    Spacer(minLength: rowGlyphSize + rowSpacing)
                    inlineDelta(displayedDelta, currency: deltaCurrency)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.vertical, rowVerticalPadding)
        .animation(.easeOut(duration: 0.18), value: displaysConversion)
    }

    private func desktopEntryRow(_ row: EntryRow) -> some View {
        let entry = row.current
        let revealsConversion = revealsConversion(for: entry)
        return HStack(alignment: .center, spacing: rowSpacing) {
            entryIdentity(row)

            Spacer(minLength: minimumColumnSpacing)

            VStack(alignment: .trailing, spacing: 3) {
                entryAmount(entry)
                if let entryDelta = row.delta {
                    inlineDelta(entryDelta, currency: entry.currency)
                }
                if let converted = entry.convertedAmount,
                   hasForeignConversion(entry), revealsConversion {
                    convertedAmountLabel(converted)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .layoutPriority(0)
        }
        .padding(.vertical, rowVerticalPadding)
        .contentShape(Rectangle())
        .onHover { isHovering in
            updateHoveredEntry(entry.id, isHovering: isHovering)
        }
        .animation(.easeOut(duration: 0.18), value: revealsConversion)
    }

    private func entryIdentity(_ row: EntryRow) -> some View {
        let entry = row.current
        return HStack(alignment: .center, spacing: rowSpacing) {
            GlyphBadge(
                systemName: row.accountKind.iconName,
                tint: row.accountKind.tint,
                size: rowGlyphSize
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.accountName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.notionInk)
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
        entry.convertedAmount != nil && entry.currency != snapshot.homeCurrency
    }

    private func revealsConversion(for entry: PortfolioSnapshot.Entry) -> Bool {
        hoveredEntryID == entry.id
    }

    private func convertedDelta(for row: EntryRow) -> Decimal? {
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
                .currency(code: snapshot.homeCurrency)
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
        let currency = usesHomeCurrency ? snapshot.homeCurrency : entry.currency
        let amount = usesHomeCurrency ? (entry.convertedAmount ?? entry.amount) : entry.amount
        return HStack(spacing: 6) {
            Text(verbatim: currency)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(Color.notionInkMuted)

            if showsConversionAffordance {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.notionInkMuted.opacity(0.8))
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
            .foregroundStyle(Color.notionInk)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentTransition(.numericText())
        }
        .padding(.horizontal, 9)
        .frame(width: amountBoxWidth, height: 38)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.notionSurfaceAlt.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.notionBorder, lineWidth: 0.75)
        )
    }

    // MARK: - Change breakdown

    @ViewBuilder
    private func changeBreakdownCard(_ breakdown: ChangeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            detailSectionTitle("portfolioSnapshot.detail.change.title")

            let rows = breakdown.displayRows
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    breakdownRow(
                        row,
                        rateChanges: row.id == "fx" ? breakdown.fxRateChanges : []
                    )
                    if index < rows.count - 1 {
                        Divider()
                            .opacity(0.35)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: detailCardCornerRadius, padding: detailCardPadding)
    }

    @ViewBuilder
    private func breakdownRow(_ row: BreakdownRow, rateChanges: [FXRateChange]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.titleKey)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.notionInk)
                    .lineLimit(1)
                Spacer(minLength: 8)

                Text(verbatim: signedAmount(row.amount, currency: snapshot.homeCurrency))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(amountTint(row.amount))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }

            Text(row.subtitleKey)
                .font(.caption)
                .foregroundStyle(Color.notionInkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !rateChanges.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("portfolioSnapshot.detail.rates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.notionInkSecondary)
                        Spacer()
                        Text(verbatim: snapshot.homeCurrency)
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(Color.notionInkMuted)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)

                    Divider().opacity(0.35)

                    ForEach(Array(rateChanges.enumerated()), id: \.element.id) { index, change in
                        HStack(spacing: 10) {
                            Text(verbatim: change.currency)
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(Color.notionInk)
                                .frame(width: 34, alignment: .leading)

                            Text(verbatim: formattedRate(change.oldRate))
                                .foregroundStyle(Color.notionInkMuted)

                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.notionInkMuted.opacity(0.65))

                            Text(verbatim: formattedRate(change.newRate))
                                .foregroundStyle(Color.notionInk)
                                .fontWeight(.medium)

                            Spacer(minLength: 0)
                        }
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)

                        if index < rateChanges.count - 1 {
                            Divider()
                                .opacity(0.22)
                                .padding(.leading, 11)
                        }
                    }
                }
                .background(
                    Color.notionSurfaceAlt.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
        .padding(.vertical, 10)
    }

    private func formattedRate(_ rate: Decimal) -> String {
        rate.formatted(.number.precision(.fractionLength(2...4)).locale(locale))
    }

    // MARK: - Inline delta helper

    private func detailSectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.notionInk)
    }

    @ViewBuilder
    private func inlineDelta(_ amount: Decimal, currency: String) -> some View {
        let isPositive = amount >= 0
        let tint: Color = isPositive ? .notionGreen : .notionOrange
        HStack(spacing: 3) {
            Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                .font(.caption2.weight(.bold))
            Text(verbatim: signedAmount(amount, currency: currency))
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(tint)
    }

    // MARK: - Grouping & comparison

    /// Pairs each current entry with its prior counterpart (matched by
    /// `holdingId`), grouped and sorted for stable display.
    private var memberGroups: [MemberGroup] {
        let priorByHolding: [UUID: PortfolioSnapshot.Entry] = {
            guard let previous else { return [:] }
            var map: [UUID: PortfolioSnapshot.Entry] = [:]
            for entry in previous.entries {
                if let id = entry.holdingId { map[id] = entry }
            }
            return map
        }()
        let kindByHolding = accountKindByHolding

        let grouped = Dictionary(grouping: snapshot.entries, by: { $0.memberName })
        return grouped.keys.sorted().map { member in
            let entries = (grouped[member] ?? [])
                .sorted { lhs, rhs in
                    if lhs.accountName == rhs.accountName {
                        return lhs.currency < rhs.currency
                    }
                    return lhs.accountName < rhs.accountName
                }
                .map { entry -> EntryRow in
                    let prior = entry.holdingId.flatMap { priorByHolding[$0] }
                    // Per-row delta is computed in the holding's *native*
                    // currency so the displayed value matches the row's
                    // primary number. Mismatched currencies (a holding
                    // that switched currency between snapshots) are not
                    // comparable on a single line, so we suppress the delta.
                    let delta: Decimal? = {
                        guard let prior, prior.currency == entry.currency else { return nil }
                        return entry.amount - prior.amount
                    }()
                    // Prefer the kind captured in the snapshot itself
                    // (added later) — relying on live `holding.account`
                    // traversal is unreliable on iOS when relationships
                    // are lazily loaded, which can flip the icon to the
                    // `.cash` fallback for non-cash kinds.
                    let kind = entry.accountKind
                        ?? entry.holdingId.flatMap { kindByHolding[$0] }
                        ?? .cash
                    return EntryRow(
                        current: entry,
                        prior: prior,
                        delta: delta,
                        accountKind: kind
                    )
                }
            let total = entries
                .compactMap { $0.current.convertedAmount }
                .reduce(Decimal(0), +)
            let memberDelta: Decimal? = {
                guard previous != nil else { return nil }
                let now = entries.compactMap { $0.current.convertedAmount }.reduce(Decimal(0), +)
                let was = entries.compactMap { $0.prior?.convertedAmount }.reduce(Decimal(0), +)
                // Only meaningful when at least one entry resolves both sides.
                let hasAnyPrior = entries.contains { $0.prior != nil }
                return hasAnyPrior ? (now - was) : nil
            }()
            return MemberGroup(
                member: member,
                entries: entries,
                total: total,
                delta: memberDelta
            )
        }
    }

    private struct MemberGroup {
        let member: String
        let entries: [EntryRow]
        let total: Decimal
        let delta: Decimal?
    }

    private struct EntryRow {
        let current: PortfolioSnapshot.Entry
        let prior: PortfolioSnapshot.Entry?
        let delta: Decimal?
        let accountKind: AccountKind
    }

    private struct TotalDelta {
        let amount: Decimal
        let percent: Double?
        let previousMonth: Date
    }

    private var totalDelta: TotalDelta? {
        guard let previous else { return nil }
        let amount = snapshot.totalAmount - previous.totalAmount
        let percent: Double? = {
            guard previous.totalAmount != 0 else { return nil }
            let pct = (snapshot.totalAmount - previous.totalAmount) / previous.totalAmount
            return NSDecimalNumber(decimal: pct).doubleValue
        }()
        return TotalDelta(amount: amount, percent: percent, previousMonth: previous.periodMonth)
    }

    // MARK: - Change decomposition

    /// Splits `totalNew - totalOld` into market movement, FX impact, and
    /// manual updates (added / removed holdings).
    ///
    /// For a matched holding (same `holdingId`) priced in a foreign
    /// currency we decompose:
    ///   `Δhome = (amountNew - amountOld) / rateNew + amountOld × (1/rateNew - 1/rateOld)`
    /// where the *effective* rate is recovered from each snapshot's
    /// stored entry as `rate = amount / convertedAmount` so we don't
    /// depend on the rate-storage convention. The first term is "market
    /// movement", the second is "FX impact". Home-currency holdings have
    /// no FX component.
    ///
    /// Holdings present only in one side count as "manual updates"
    /// (added or removed). When `convertedAmount` is missing we fall
    /// back to attributing the whole delta to market movement.
    private var breakdown: ChangeBreakdown? {
        guard let previous else { return nil }
        var market: Decimal = 0
        var fx: Decimal = 0
        var manualAdded: Decimal = 0
        var manualRemoved: Decimal = 0
        var fxRateChanges: [FXRateChange] = []
        var seenFX: Set<String> = []

        let priorByHolding: [UUID: PortfolioSnapshot.Entry] = {
            var map: [UUID: PortfolioSnapshot.Entry] = [:]
            for entry in previous.entries {
                if let id = entry.holdingId { map[id] = entry }
            }
            return map
        }()
        var priorRemaining = priorByHolding

        for entry in snapshot.entries {
            let prior = entry.holdingId.flatMap { priorByHolding[$0] }
            if let prior, prior.currency == entry.currency {
                if let id = entry.holdingId { priorRemaining.removeValue(forKey: id) }
                let homeNow = entry.convertedAmount
                let homeWas = prior.convertedAmount

                if entry.currency == snapshot.homeCurrency {
                    // Home currency: 100% market.
                    if let homeNow, let homeWas {
                        market += (homeNow - homeWas)
                    }
                } else if let homeNow, let homeWas,
                          entry.amount != 0, prior.amount != 0,
                          homeNow != 0, homeWas != 0 {
                    // Effective rates have units `foreign / home`.
                    let rateNew = entry.amount / homeNow
                    let rateOld = prior.amount / homeWas
                    let marketComponent = (entry.amount - prior.amount) / rateNew
                    let fxComponent = prior.amount * (1 / rateNew - 1 / rateOld)
                    market += marketComponent
                    fx += fxComponent
                    if !seenFX.contains(entry.currency), rateNew != rateOld {
                        seenFX.insert(entry.currency)
                        fxRateChanges.append(FXRateChange(
                            currency: entry.currency,
                            oldRate: rateOld == 0 ? 0 : 1 / rateOld,
                            newRate: rateNew == 0 ? 0 : 1 / rateNew
                        ))
                    }
                } else if let homeNow, let homeWas {
                    // Missing data — attribute to market.
                    market += (homeNow - homeWas)
                }
            } else {
                // Added (no prior, or currency changed).
                if let prior {
                    // Currency changed: treat as remove + add.
                    if let id = entry.holdingId { priorRemaining.removeValue(forKey: id) }
                    if let homeWas = prior.convertedAmount { manualRemoved -= homeWas }
                }
                if let homeNow = entry.convertedAmount {
                    manualAdded += homeNow
                }
            }
        }

        // Anything left in `priorRemaining` was removed this period.
        for (_, prior) in priorRemaining {
            if let homeWas = prior.convertedAmount {
                manualRemoved -= homeWas
            }
        }

        return ChangeBreakdown(
            market: market,
            fx: fx,
            manualAdded: manualAdded,
            manualRemoved: manualRemoved,
            fxRateChanges: fxRateChanges.sorted { $0.currency < $1.currency }
        )
    }

    private struct FXRateChange: Identifiable {
        var id: String { currency }
        let currency: String
        let oldRate: Decimal
        let newRate: Decimal
    }

    private struct ChangeBreakdown {
        let market: Decimal
        let fx: Decimal
        let manualAdded: Decimal
        let manualRemoved: Decimal
        let fxRateChanges: [FXRateChange]

        var manualNet: Decimal { manualAdded + manualRemoved }
        var hasContent: Bool {
            fx != 0 || manualNet != 0
        }

        var displayRows: [BreakdownRow] {
            var rows: [BreakdownRow] = []
            if fx != 0 {
                rows.append(BreakdownRow(
                    id: "fx",
                    titleKey: "portfolioSnapshot.detail.change.fx",
                    subtitleKey: "portfolioSnapshot.detail.change.fx.hint",
                    amount: fx
                ))
            }
            if manualNet != 0 {
                rows.append(BreakdownRow(
                    id: "manual",
                    titleKey: "portfolioSnapshot.detail.change.manual",
                    subtitleKey: "portfolioSnapshot.detail.change.manual.hint",
                    amount: manualNet
                ))
            }
            return rows
        }
    }

    private struct BreakdownRow: Identifiable {
        let id: String
        let titleKey: LocalizedStringKey
        let subtitleKey: LocalizedStringKey
        let amount: Decimal
    }

    // MARK: - Formatting helpers

    private var pageHorizontalInset: CGFloat {
        #if os(macOS)
        24
        #else
        10
        #endif
    }

    private var detailCardPadding: CGFloat {
        #if os(macOS)
        20
        #else
        12
        #endif
    }

    private var detailCardCornerRadius: CGFloat {
        #if os(macOS)
        16
        #else
        14
        #endif
    }

    private var memberAvatarSize: CGFloat {
        #if os(macOS)
        24
        #else
        26
        #endif
    }

    private var amountBoxWidth: CGFloat {
        #if os(macOS)
        190
        #else
        148
        #endif
    }

    private var rowGlyphSize: CGFloat { 28 }

    private var rowSpacing: CGFloat {
        #if os(macOS)
        12
        #else
        8
        #endif
    }

    private var minimumColumnSpacing: CGFloat {
        #if os(macOS)
        8
        #else
        6
        #endif
    }

    private var rowVerticalPadding: CGFloat {
        #if os(macOS)
        9
        #else
        8
        #endif
    }

    private func signedAmount(_ value: Decimal, currency: String) -> String {
        let isPositive = value >= 0
        let abs = value < 0 ? -value : value
        let formatted = abs.formatted(
            .currency(code: currency)
                .locale(locale)
                .precision(.fractionLength(0))
        )
        return (isPositive ? "+" : "−") + formatted
    }

    private func signedPercent(_ value: Double) -> String {
        let isPositive = value >= 0
        let abs = Swift.abs(value)
        let formatted = abs.formatted(.percent.precision(.fractionLength(1)))
        return (isPositive ? "+" : "−") + formatted
    }

    private func amountTint(_ value: Decimal) -> Color {
        if value == 0 { return .secondary }
        return value > 0 ? .notionGreen : .notionOrange
    }

    private func vsPreviousLabel(_ previousMonth: Date) -> String {
        let template = String(localized: "portfolioSnapshot.detail.change.vs")
        let label = previousMonth.formatted(
            .dateTime.year().month(.abbreviated).locale(locale)
        )
        return template.replacingOccurrences(of: "{month}", with: label)
    }

    private var footnoteDateFormat: Date.FormatStyle {
        Date.FormatStyle.dateTime.year().month().day().locale(locale)
    }

    private var capturedDate: Date {
        resolvedCapturedDate ?? snapshot.periodMonth
    }

    private func resolveCapturedDateIfNeeded() {
        guard resolvedCapturedDate == nil else { return }
        resolvedCapturedDate = PortfolioSnapshotService.capturedDate(for: snapshot, context: context)
    }

    private func delete() {
        do {
            try PortfolioSnapshotService.delete(snapshot, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Looks up the chronologically prior `PortfolioSnapshot` (same home
    /// currency) directly from the model context. Only runs when the
    /// caller didn't pass `previous` explicitly, so existing call sites
    /// keep their precomputed neighbour.
    private func resolvePreviousIfNeeded() {
        guard explicitPrevious == nil, resolvedPrevious == nil else { return }
        let month = snapshot.periodMonth
        let currency = snapshot.homeCurrency
        var descriptor = FetchDescriptor<PortfolioSnapshot>(
            predicate: #Predicate { $0.periodMonth < month && $0.homeCurrency == currency },
            sortBy: [SortDescriptor(\.periodMonth, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        resolvedPrevious = (try? context.fetch(descriptor))?.first
    }

    /// Resolves each captured entry's holding to the live account's
    /// `kind`, so we can render the same glyph badge used elsewhere
    /// (account list, batch entry). Falls back to `.cash` for entries
    /// whose holding has been deleted since capture.
    /// Live members keyed by name, so each captured `memberName` can be
    /// matched to the current `Member` for avatar display. Best-effort:
    /// renamed members won't match.
    private var memberByName: [String: Member] {
        Dictionary(members.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var accountKindByHolding: [UUID: AccountKind] {
        let ids = Set(snapshot.entries.compactMap(\.holdingId))
        guard !ids.isEmpty else { return [:] }
        // SwiftData `#Predicate` with `Set.contains` on captured values
        // is unreliable on macOS — fetch all and filter in Swift.
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        var map: [UUID: AccountKind] = [:]
        for holding in holdings where ids.contains(holding.id) {
            if let kind = holding.account?.kind {
                map[holding.id] = kind
            }
        }
        return map
    }

    /// Captured rates rebuilt as `quote → rate` (matching Frankfurter's
    /// `1 home == rate × quote` convention) so the editor reuses the
    /// snapshot's historical rates instead of refetching live data.
    private var lockedRatesForEdit: [String: Decimal] {
        var map: [String: Decimal] = [:]
        for rate in snapshot.rates where rate.base == snapshot.homeCurrency {
            map[rate.quote] = rate.rate
        }
        return map
    }

    /// Captured per-holding amounts keyed by `holdingId`, used to seed
    /// the editor with the snapshot's recorded values rather than the
    /// previous month's. Entries whose holding has since been deleted
    /// (no `holdingId`) are skipped — the row simply won't appear.
    private var lockedBaselineForEdit: [UUID: Decimal] {
        var map: [UUID: Decimal] = [:]
        for entry in snapshot.entries {
            guard let holdingId = entry.holdingId else { continue }
            map[holdingId] = entry.amount
        }
        return map
    }
}

private extension PortfolioSnapshotDetailView {
    static let unassignedMemberSeed = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

#Preview {
    let env = PreviewSampleData.seededContainer()
    return NavigationStack {
        PortfolioSnapshotDetailView(snapshot: env.seed.latestPortfolioSnapshot)
    }
    .modelContainer(env.container)
}
