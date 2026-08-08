import SwiftUI
import SwiftData

/// Lists physical `Possession` records (real estate, vehicles, electronics, …)
/// grouped by category. Surfaced as the "Possessions" tab inside `AssetsView`.
///
/// Empty state guides the user to create their first possession. Each row shows
/// the owner, current value in its native currency, and the category badge.
/// Sold possessions are grouped into a separate "Sold" section and rendered with
/// reduced emphasis.
struct PossessionsView: View {
    var addRequest: Int = 0

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query(sort: \Possession.createdAt, order: .reverse) private var possessions: [Possession]
    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query private var rates: [FXRate]

    @State private var editingPossession: Possession?
    @State private var newPossessionDraft: Possession?
    @State private var newPossessionSaved: Bool = false
    /// Strong reference to the in-flight draft. The sheet's `item`
    /// binding is set to `nil` *before* `onDismiss` fires, so we can't
    /// rely on it to clean up the draft on swipe-down dismissal.
    @State private var pendingNewPossession: Possession?
    @State private var possessionPendingDeletion: Possession?

    /// Per-render derivation: pre-bucket possessions by sold/active and by
    /// category, and compute the home-currency *purchase-cost* total
    /// once. The Possessions tab is intentionally a purchase-cost ledger and
    /// does not surface manual revaluations or any depreciation model,
    /// so we ignore `currentValue` here and sum `purchasePrice` directly.
    private struct Derivation {
        var purchaseCostTotal: Decimal
        var missingCurrencies: [String]
        var active: [Possession]
        var sold: [Possession]
        var byCategory: [PossessionCategory: [Possession]]
        var categoryPurchaseCost: [PossessionCategory: Decimal]
    }

    private func derive() -> Derivation {
        _ = rates.count // keep reactive to FX updates
        let cache = FXService.RateCache.load(in: context)
        var active: [Possession] = []
        var sold: [Possession] = []
        var byCategory: [PossessionCategory: [Possession]] = [:]
        var categoryPurchaseCost: [PossessionCategory: Decimal] = [:]
        var total: Decimal = 0
        var missing: Set<String> = []
        active.reserveCapacity(possessions.count)
        for possession in possessions {
            if possession.isSold {
                sold.append(possession)
                continue
            }
            active.append(possession)
            byCategory[possession.category, default: []].append(possession)
            let converted: Decimal?
            if possession.purchaseCurrency == homeCurrency {
                converted = possession.purchasePrice
            } else {
                converted = cache.convert(
                    amount: possession.purchasePrice,
                    from: possession.purchaseCurrency,
                    to: homeCurrency
                )
            }
            if let value = converted {
                total += value
                categoryPurchaseCost[possession.category, default: 0] += value
            } else {
                missing.insert(possession.purchaseCurrency)
            }
        }
        return Derivation(
            purchaseCostTotal: total,
            missingCurrencies: missing.sorted(),
            active: active,
            sold: sold,
            byCategory: byCategory,
            categoryPurchaseCost: categoryPurchaseCost
        )
    }

    var body: some View {
        let derivation: Derivation = members.isEmpty || possessions.isEmpty
            ? Derivation(
                purchaseCostTotal: 0,
                missingCurrencies: [],
                active: [],
                sold: [],
                byCategory: [:],
                categoryPurchaseCost: [:]
            )
            : derive()
        return content(derivation: derivation)
            .onChange(of: addRequest) { _, _ in
                guard !members.isEmpty else { return }
                presentNewPossession()
            }
            .modifier(PossessionsSheetsModifier(
                newPossessionDraft: $newPossessionDraft,
                newPossessionSaved: $newPossessionSaved,
                pendingNewPossession: $pendingNewPossession,
                editingPossession: $editingPossession,
                possessionPendingDeletion: $possessionPendingDeletion,
                context: context
            ))
    }

    @ViewBuilder
    private func content(derivation: Derivation) -> some View {
        if members.isEmpty {
            ContentUnavailableView(
                "possession.empty.noMember.title",
                systemImage: "person.2",
                description: Text("possession.empty.noMember.hint")
            )
            .padding(.top, 48)
        } else if possessions.isEmpty {
            emptyState
        } else {
            VStack(spacing: 20) {
                summaryCard(derivation: derivation)
                categorizedCards(derivation: derivation)
                if !derivation.sold.isEmpty {
                    soldCard(derivation: derivation)
                }
            }
        }
    }

    // MARK: - Cards

    private func summaryCard(derivation: Derivation) -> some View {
        HStack(alignment: .center, spacing: 16) {
            summaryCardText(derivation: derivation)
            Spacer(minLength: 0)
            #if os(macOS)
            Button {
                presentNewPossession()
            } label: {
                Label {
                    Text("possession.new.title")
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            #endif
        }
        .glassCard()
    }

    private func summaryCardText(derivation: Derivation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Eyebrow row — mirrors the Financial hero ("NET WORTH · CNY").
            HStack(spacing: 6) {
                Text("possession.total.title")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: homeCurrency)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(
                derivation.purchaseCostTotal,
                format: .currency(code: homeCurrency)
                    .locale(locale)
                    .precision(.fractionLength(0))
            )
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Color.notionInk)
            if !derivation.missingCurrencies.isEmpty {
                Label {
                    Text(missingRatesMessage(derivation.missingCurrencies))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                .font(.footnote)
                .padding(.top, 4)
            }
            Text(possessionCountFootnote(activeCount: derivation.active.count))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func categorizedCards(derivation: Derivation) -> some View {
        let buckets: [(PossessionCategory, [Possession], Decimal)] = PossessionCategory.allCases.compactMap { category in
            guard let bucket = derivation.byCategory[category], !bucket.isEmpty else { return nil }
            return (category, bucket, derivation.categoryPurchaseCost[category] ?? 0)
        }
        #if os(macOS)
        let pairs = stride(from: 0, to: buckets.count, by: 2).map { start in
            Array(buckets[start..<min(start + 2, buckets.count)])
        }
        VStack(spacing: 16) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(pair.enumerated()), id: \.offset) { _, item in
                        categorySection(
                            category: item.0,
                            possessions: item.1,
                            purchaseCost: item.2
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    if pair.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        #else
        ForEach(buckets, id: \.0) { item in
            categorySection(
                category: item.0,
                possessions: item.1,
                purchaseCost: item.2
            )
        }
        #endif
    }

    private func categorySection(
        category: PossessionCategory,
        possessions: [Possession],
        purchaseCost: Decimal
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: category.iconName)
                    .foregroundStyle(category.tint)
                Text(LocalizedStringKey(category.localizationKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                HStack(spacing: 6) {
                    Text(itemCountFootnote(count: possessions.count))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text(
                        purchaseCost,
                        format: .currency(code: homeCurrency)
                            .locale(locale)
                            .precision(.fractionLength(0))
                    )
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(possessions.enumerated()), id: \.element.id) { index, possession in
                    possessionRow(possession)
                    if index < possessions.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func soldCard(derivation: Derivation) -> some View {
        let soldPossessions = derivation.sold
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(.secondary)
                Text("possession.section.sold")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(verbatim: "\(soldPossessions.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(soldPossessions.enumerated()), id: \.element.id) { index, possession in
                    possessionRow(possession)
                        .opacity(0.7)
                    if index < soldPossessions.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func possessionRow(_ possession: Possession) -> some View {
        Button {
            editingPossession = possession
        } label: {
            HStack(alignment: .top, spacing: 12) {
#if os(macOS)
                GlyphBadge(
                    systemName: possession.iconName ?? possession.category.iconName,
                    tint: possession.category.tint
                )
#endif
                VStack(alignment: .leading, spacing: 4) {
                    // Line 1: name
                    Text(verbatim: possession.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)

                    // Line 2: category · owner · currency
                    Text(verbatim: rowSubtitle(for: possession))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Line 3: purchase cost
                    HStack(spacing: 6) {
                        Text("possession.row.purchaseCost")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(
                            possession.purchasePrice,
                            format: .currency(code: possession.purchaseCurrency).locale(locale)
                        )
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    }

                    // Line 4: purchased {date}
                    Text(purchasedOnText(for: possession))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    // Line 5: subtle valuation placeholder (active only) —
                    // reserved for a future revaluation feature. Kept
                    // secondary so it never competes with the purchase
                    // ledger. Sold possessions show their sale info instead.
                    if possession.isSold {
                        Text("possession.badge.sold")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("possession.row.estimatedValueNotSet")
                            .font(.caption2)
                            .foregroundStyle(.tertiary.opacity(0.7))
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingPossession = possession
            } label: {
                Label { Text("common.action.edit") } icon: { Image(systemName: "pencil") }
            }
            Button(role: .destructive) {
                possessionPendingDeletion = possession
            } label: {
                Label { Text("common.action.delete") } icon: { Image(systemName: "trash") }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "possession.empty.title",
                systemImage: "house.and.flag",
                description: Text("possession.empty.hint")
            )
            Button {
                presentNewPossession()
            } label: {
                Label {
                    Text("possession.new.title")
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.top, 32)
    }

    // MARK: - Derived

    /// Compose the secondary line: "Category · Owner · CUR".
    /// Owner is omitted when missing so the dot separators stay clean.
    private func rowSubtitle(for possession: Possession) -> String {
        let category = NSLocalizedString(possession.category.localizationKey, comment: "")
        var parts: [String] = [category]
        if let member = possession.member {
            parts.append(member.name)
        }
        parts.append(possession.purchaseCurrency)
        return parts.joined(separator: " · ")
    }

    private func purchasedOnText(for possession: Possession) -> String {
        let date = possession.purchaseDate.formatted(.dateTime.year().month(.abbreviated).locale(locale))
        let template = String(localized: "possession.row.purchasedOn")
        return template.replacingOccurrences(of: "{date}", with: date)
    }

    private func possessionCountFootnote(activeCount: Int) -> String {
        let template = String(localized: "possession.count.active")
        return template.replacingOccurrences(of: "{count}", with: String(activeCount))
    }

    private func itemCountFootnote(count: Int) -> String {
        let template = String(localized: "possession.section.itemCount")
        return template.replacingOccurrences(of: "{count}", with: String(count))
    }

    private func missingRatesMessage(_ currencies: [String]) -> String {
        let list = currencies.joined(separator: ", ")
        let template = String(localized: "assets.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: list)
    }

    // MARK: - Actions

    private func presentNewPossession() {
        guard let defaultMember = members.first else { return }
        // Note: assigning a managed `Member` to the draft's relationship
        // causes SwiftData to auto-insert the draft into the same context.
        // We therefore explicitly insert here and rely on the sheet's
        // `onDismiss` to delete the draft if the user cancels or swipes
        // the sheet away without saving.
        let draft = Possession(
            name: "",
            category: .realEstate,
            purchasePrice: 0,
            purchaseCurrency: homeCurrency,
            purchaseDate: .now,
            member: defaultMember
        )
        context.insert(draft)
        newPossessionSaved = false
        pendingNewPossession = draft
        newPossessionDraft = draft
    }
}

/// Bundles the Possessions screen's sheet + delete-confirmation modifiers so
/// `PossessionsView.body` stays comfortably under the function-length budget.
private struct PossessionsSheetsModifier: ViewModifier {
    @Binding var newPossessionDraft: Possession?
    @Binding var newPossessionSaved: Bool
    @Binding var pendingNewPossession: Possession?
    @Binding var editingPossession: Possession?
    @Binding var possessionPendingDeletion: Possession?
    let context: ModelContext

    func body(content: Content) -> some View {
        content
            .sheet(
                item: $newPossessionDraft,
                onDismiss: {
                    // Covers both Cancel taps and interactive swipe-down
                    // dismissal on iOS. By the time `onDismiss` fires the
                    // sheet's `item` binding is already nil, so we use
                    // `pendingNewPossession` to reach the draft we inserted.
                    if !newPossessionSaved, let draft = pendingNewPossession {
                        context.delete(draft)
                    }
                    pendingNewPossession = nil
                    newPossessionSaved = false
                }
            ) { draft in
                PossessionFormView(possession: draft, isNew: true) { saved in
                    newPossessionSaved = saved
                }
            }
            .sheet(item: $editingPossession) { possession in
                PossessionFormView(possession: possession, isNew: false) { _ in
                    editingPossession = nil
                }
            }
            // Use `.alert` rather than `.confirmationDialog` here: when
            // triggered from a row's context menu inside a `LazyVStack`,
            // a confirmation dialog on iOS can race with the menu's
            // dismissal animation (requiring a second tap) and anchors
            // its popover oddly on iPad. An alert is system-modal and
            // centered, which avoids both issues.
            .alert(
                Text("possession.delete.confirm.title"),
                isPresented: Binding(
                    get: { possessionPendingDeletion != nil },
                    set: { if !$0 { possessionPendingDeletion = nil } }
                ),
                presenting: possessionPendingDeletion
            ) { possession in
                Button(role: .destructive) {
                    context.delete(possession)
                    possessionPendingDeletion = nil
                } label: {
                    Text("common.action.delete")
                }
                Button(role: .cancel) { possessionPendingDeletion = nil } label: { Text("common.action.cancel") }
            } message: { _ in
                Text("possession.delete.confirm.message")
            }
    }
}

#if DEBUG
#Preview("Possessions · seeded") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        ScrollView {
            PossessionsView()
                .padding(24)
        }
        .ambientBackground()
    }
    .modelContainer(PreviewSampleData.container())
}

#Preview("Possessions · empty") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        ScrollView {
            PossessionsView()
                .padding(24)
        }
        .ambientBackground()
    }
    .modelContainer(PreviewSampleData.container())
}
#endif
