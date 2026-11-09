import SwiftUI
import SwiftData

/// Lists physical `Possession` records (real estate, vehicles, electronics, …)
/// grouped by category. Surfaced as the "Possessions" tab inside `AssetsView`.
///
/// Laid out like the Financial tab: a purchase-cost hero, then one breakdown
/// card per category whose rows show the owner, holding period, and native
/// purchase price (plus its home-currency equivalent). Sold possessions are
/// grouped into a separate "Sold" card and rendered with reduced emphasis.
struct PossessionsView: View {
    var addRequest: Int = 0

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.possessionInspector) private var inspector

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
        /// Home-currency purchase cost for foreign-currency possessions
        /// (active and sold) whose rate is available, keyed by id.
        var homeEquivalents: [UUID: Decimal] = [:]
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
        var homeEquivalents: [UUID: Decimal] = [:]
        active.reserveCapacity(possessions.count)
        for possession in possessions {
            let converted: Decimal?
            if possession.purchaseCurrency == homeCurrency {
                converted = possession.purchasePrice
            } else {
                converted = cache.convert(
                    amount: possession.purchasePrice,
                    from: possession.purchaseCurrency,
                    to: homeCurrency
                )
                homeEquivalents[possession.id] = converted
            }
            if possession.isSold {
                sold.append(possession)
                continue
            }
            active.append(possession)
            byCategory[possession.category, default: []].append(possession)
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
            categoryPurchaseCost: categoryPurchaseCost,
            homeEquivalents: homeEquivalents
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
                // The total rides on the showcase as its nameplate; the full
                // hero card only remains when nothing active is on display.
                if derivation.active.isEmpty {
                    heroSummary(derivation: derivation, compact: false).glassCard()
                } else {
                    showcase(derivation: derivation)
                }
                listCards(derivation: derivation)
            }
        }
    }

    // MARK: - Cards

    /// Mirrors the Financial tab's hero: eyebrow, headline total, footnotes,
    /// and (on macOS) the primary action trailing the text. `compact` is the
    /// showcase nameplate: a smaller total with the item count beside it.
    private func heroSummary(derivation: Derivation, compact: Bool) -> some View {
        #if os(macOS)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                heroTextBlock(derivation: derivation, compact: compact)
                Spacer()
                addPossessionButton(compact: compact)
            }
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                heroTextBlock(derivation: derivation, compact: compact)
                addPossessionButton(compact: compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #else
        // iOS exposes "New possession" through the navigation bar "+".
        heroTextBlock(derivation: derivation, compact: compact)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    private func heroTextBlock(derivation: Derivation, compact: Bool) -> some View {
        PossessionsTotalSummary(
            total: derivation.purchaseCostTotal,
            homeCurrency: homeCurrency,
            activeCount: derivation.active.count,
            missingCurrencies: derivation.missingCurrencies,
            compact: compact
        )
    }

    #if os(macOS)
    private func addPossessionButton(compact: Bool) -> some View {
        Button {
            presentNewPossession()
        } label: {
            Label {
                Text("possession.new.title")
            } icon: {
                Image(systemName: "plus")
            }
        }
        .controlSize(compact ? .regular : .large)
        .cairnProminentButtonStyle()
        // Hidden while a showcase item is open; Liquid Glass would otherwise
        // shine through the dimmed page. Opacity keeps the header layout.
        .opacity(inspector?.inspectedID == nil ? 1 : 0)
        .disabled(inspector?.inspectedID != nil)
    }
    #endif

    private func cardSpecs(derivation: Derivation) -> [PossessionListCard] {
        var cards: [PossessionListCard] = PossessionCategory.allCases.compactMap { category in
            guard let bucket = derivation.byCategory[category], !bucket.isEmpty else { return nil }
            let subtotal = (derivation.categoryPurchaseCost[category] ?? 0).formatted(
                .currency(code: homeCurrency)
                    .locale(locale)
                    .precision(.fractionLength(0))
            )
            return PossessionListCard(
                id: category.rawValue,
                titleKey: LocalizedStringKey(category.localizationKey),
                accessory: "\(itemCountFootnote(count: bucket.count)) · \(subtotal)",
                possessions: bucket,
                dimmed: false
            )
        }
        if !derivation.sold.isEmpty {
            cards.append(PossessionListCard(
                id: "sold",
                titleKey: "possession.section.sold",
                accessory: itemCountFootnote(count: derivation.sold.count),
                possessions: derivation.sold,
                dimmed: true
            ))
        }
        return cards
    }

    /// Single column everywhere except wide macOS windows, where cards are
    /// packed into two top-aligned columns (each card goes to the shorter
    /// column) so mixed card heights don't leave holes.
    @ViewBuilder
    private func listCards(derivation: Derivation) -> some View {
        let cards = cardSpecs(derivation: derivation)
        #if os(macOS)
        if cards.count > 1 {
            let columns = PossessionListCard.balancedColumns(cards)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    cardColumn(columns.0, homeEquivalents: derivation.homeEquivalents)
                        .frame(minWidth: 380, maxWidth: .infinity)
                    cardColumn(columns.1, homeEquivalents: derivation.homeEquivalents)
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
                cardColumn(cards, homeEquivalents: derivation.homeEquivalents)
            }
        } else {
            cardColumn(cards, homeEquivalents: derivation.homeEquivalents)
        }
        #else
        cardColumn(cards, homeEquivalents: derivation.homeEquivalents)
        #endif
    }

    private func cardColumn(_ cards: [PossessionListCard], homeEquivalents: [UUID: Decimal]) -> some View {
        VStack(spacing: 20) {
            ForEach(cards) { card in
                AssetsBreakdownCard(titleKey: card.titleKey, accessory: card.accessory) {
                    possessionRows(card.possessions, homeEquivalents: homeEquivalents, dimmed: card.dimmed)
                }
            }
        }
    }

    private func possessionRows(
        _ possessions: [Possession],
        homeEquivalents: [UUID: Decimal],
        dimmed: Bool
    ) -> some View {
        ForEach(Array(possessions.enumerated()), id: \.element.id) { index, possession in
            possessionRow(possession, homeEquivalent: homeEquivalents[possession.id])
                .opacity(dimmed ? 0.7 : 1)
            if index < possessions.count - 1 {
                Divider().opacity(0.35)
            }
        }
    }

    /// One breakdown row per possession, sharing the Financial tab's
    /// leading-mark / title / trailing-amount columns.
    private func possessionRow(_ possession: Possession, homeEquivalent: Decimal?) -> some View {
        Button {
            editingPossession = possession
        } label: {
            AssetsBreakdownRow(
                leading: {
                    PossessionPhotoBadge(
                        photoData: possession.photoData,
                        systemName: possession.iconName ?? possession.category.iconName,
                        tint: possession.category.tint
                    )
                },
                title: possession.name,
                caption: rowCaption(for: possession),
                trailing: { rowTrailing(for: possession, homeEquivalent: homeEquivalent) },
                share: nil,
                showsShare: false,
                monthDelta: nil,
                currencyCode: homeCurrency,
                locale: locale
            )
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

    /// Native purchase price, with the home-currency equivalent underneath
    /// for foreign purchases so the column still reads in one currency.
    private func rowTrailing(for possession: Possession, homeEquivalent: Decimal?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                AssetsBreakdownAmount(
                    amount: possession.purchasePrice,
                    currencyCode: possession.purchaseCurrency,
                    locale: locale
                )
                if let converted = homeEquivalent {
                    Text(
                        converted,
                        format: .currency(code: homeCurrency)
                            .locale(locale)
                            .precision(.fractionLength(0))
                    )
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            // Amounts never wrap mid-number; the name column wraps instead.
            .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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
            .controlSize(.large)
            .cairnProminentButtonStyle()
        }
        .padding(.top, 32)
    }

    // MARK: - Derived

    /// "Owner · Mar 2023", or "Owner · Mar 2023 – Jun 2024" once sold.
    /// Owner is omitted when missing so the separators stay clean.
    private func rowCaption(for possession: Possession) -> String {
        let style = Date.FormatStyle.dateTime.year().month(.abbreviated).locale(locale)
        var held = possession.purchaseDate.formatted(style)
        if let saleDate = possession.saleDate {
            held += " – " + saleDate.formatted(style)
        }
        guard let member = possession.member else { return held }
        return "\(member.name) · \(held)"
    }

    private func itemCountFootnote(count: Int) -> String {
        let template = String(localized: "possession.section.itemCount")
        return template.replacingOccurrences(of: "{count}", with: String(count))
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

extension PossessionsView {
    private func showcase(derivation: Derivation) -> some View {
        PossessionShowcaseView(
            header: { heroSummary(derivation: derivation, compact: true) },
            shelves: PossessionShowcaseLayout.shelves(byCategory: derivation.byCategory) { possession in
                possession.purchaseCurrency == homeCurrency
                    ? possession.purchasePrice
                    : derivation.homeEquivalents[possession.id]
            },
            priceText: { possession in
                possession.purchasePrice.formatted(
                    .currency(code: possession.purchaseCurrency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
            },
            onSelect: { editingPossession = $0 },
            onDelete: { possessionPendingDeletion = $0 }
        )
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
