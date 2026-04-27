import SwiftUI
import SwiftData

/// Lists physical `Asset` records (real estate, vehicles, electronics, …)
/// grouped by category. Surfaced as the "Assets" tab inside `OverviewView`.
///
/// Empty state guides the user to create their first asset. Each row shows
/// the owner, current value in its native currency, and the category badge.
/// Sold assets are grouped into a separate "Sold" section and rendered with
/// reduced emphasis.
struct AssetsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query(sort: \Asset.createdAt, order: .reverse) private var assets: [Asset]
    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query private var rates: [FXRate]

    @State private var editingAsset: Asset?
    @State private var newAssetDraft: Asset?
    @State private var assetPendingDeletion: Asset?

    /// Per-render derivation: pre-bucket assets by sold/active and by
    /// category, and compute the home-currency *purchase-cost* total
    /// once. The Assets tab is intentionally a purchase-cost ledger and
    /// does not surface manual revaluations or any depreciation model,
    /// so we ignore `currentValue` here and sum `purchasePrice` directly.
    private struct Derivation {
        var purchaseCostTotal: Decimal
        var missingCurrencies: [String]
        var active: [Asset]
        var sold: [Asset]
        var byCategory: [AssetCategory: [Asset]]
        var categoryPurchaseCost: [AssetCategory: Decimal]
    }

    private func derive() -> Derivation {
        _ = rates.count // keep reactive to FX updates
        let cache = FXService.RateCache.load(in: context)
        var active: [Asset] = []
        var sold: [Asset] = []
        var byCategory: [AssetCategory: [Asset]] = [:]
        var categoryPurchaseCost: [AssetCategory: Decimal] = [:]
        var total: Decimal = 0
        var missing: Set<String> = []
        active.reserveCapacity(assets.count)
        for asset in assets {
            if asset.isSold {
                sold.append(asset)
                continue
            }
            active.append(asset)
            byCategory[asset.category, default: []].append(asset)
            let converted: Decimal?
            if asset.purchaseCurrency == homeCurrency {
                converted = asset.purchasePrice
            } else {
                converted = cache.convert(
                    amount: asset.purchasePrice,
                    from: asset.purchaseCurrency,
                    to: homeCurrency
                )
            }
            if let value = converted {
                total += value
                categoryPurchaseCost[asset.category, default: 0] += value
            } else {
                missing.insert(asset.purchaseCurrency)
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
        let derivation: Derivation = members.isEmpty || assets.isEmpty
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
            .modifier(toolbarModifier())
            .modifier(AssetsSheetsModifier(
                newAssetDraft: $newAssetDraft,
                editingAsset: $editingAsset,
                assetPendingDeletion: $assetPendingDeletion,
                context: context
            ))
    }

    /// Adds the iOS-only "+" toolbar button. macOS keeps the action inside
    /// the summary card because the nav bar already hosts the tab switcher.
    private func toolbarModifier() -> some ViewModifier {
        AssetsToolbarModifier(showAdd: !members.isEmpty, action: presentNewAsset)
    }

    @ViewBuilder
    private func content(derivation: Derivation) -> some View {
        if members.isEmpty {
            ContentUnavailableView(
                "asset.empty.noMember.title",
                systemImage: "person.2",
                description: Text("asset.empty.noMember.hint")
            )
            .padding(.top, 48)
        } else if assets.isEmpty {
            emptyState
        } else {
            VStack(spacing: 20) {
                summaryCard(derivation: derivation)
                trendCard
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
                presentNewAsset()
            } label: {
                Label {
                    Text("asset.new.title")
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
                Text("asset.total.title")
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
            Text(assetCountFootnote(activeCount: derivation.active.count))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    /// Cumulative asset-purchase timeline. Styled to match `TrendChartView`
    /// in the Financial tab (same `glassCard` wrapper + minHeight) so the
    /// two tabs share a consistent visual rhythm.
    private var trendCard: some View {
        AssetTrendChartView()
            .glassCard()
    }

    @ViewBuilder
    private func categorizedCards(derivation: Derivation) -> some View {
        ForEach(AssetCategory.allCases, id: \.self) { category in
            if let bucket = derivation.byCategory[category], !bucket.isEmpty {
                categorySection(
                    category: category,
                    assets: bucket,
                    purchaseCost: derivation.categoryPurchaseCost[category] ?? 0
                )
            }
        }
    }

    private func categorySection(
        category: AssetCategory,
        assets: [Asset],
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
                    Text(itemCountFootnote(count: assets.count))
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
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    assetRow(asset)
                    if index < assets.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func soldCard(derivation: Derivation) -> some View {
        let soldAssets = derivation.sold
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(.secondary)
                Text("asset.section.sold")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(verbatim: "\(soldAssets.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(soldAssets.enumerated()), id: \.element.id) { index, asset in
                    assetRow(asset)
                        .opacity(0.7)
                    if index < soldAssets.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func assetRow(_ asset: Asset) -> some View {
        Button {
            editingAsset = asset
        } label: {
            HStack(alignment: .top, spacing: 12) {
#if os(macOS)
                GlyphBadge(
                    systemName: asset.iconName ?? asset.category.iconName,
                    tint: asset.category.tint
                )
#endif
                VStack(alignment: .leading, spacing: 4) {
                    // Line 1: name
                    Text(verbatim: asset.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)

                    // Line 2: category · owner · currency
                    Text(verbatim: rowSubtitle(for: asset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Line 3: purchase cost
                    HStack(spacing: 6) {
                        Text("asset.row.purchaseCost")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(
                            asset.purchasePrice,
                            format: .currency(code: asset.purchaseCurrency).locale(locale)
                        )
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    }

                    // Line 4: purchased {date}
                    Text(purchasedOnText(for: asset))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    // Line 5: subtle valuation placeholder (active only) —
                    // reserved for a future revaluation feature. Kept
                    // secondary so it never competes with the purchase
                    // ledger. Sold assets show their sale info instead.
                    if asset.isSold {
                        Text("asset.badge.sold")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("asset.row.estimatedValueNotSet")
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
                editingAsset = asset
            } label: {
                Label { Text("common.action.edit") } icon: { Image(systemName: "pencil") }
            }
            Button(role: .destructive) {
                assetPendingDeletion = asset
            } label: {
                Label { Text("common.action.delete") } icon: { Image(systemName: "trash") }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "asset.empty.title",
                systemImage: "house.and.flag",
                description: Text("asset.empty.hint")
            )
            Button {
                presentNewAsset()
            } label: {
                Label {
                    Text("asset.new.title")
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
    private func rowSubtitle(for asset: Asset) -> String {
        let category = NSLocalizedString(asset.category.localizationKey, comment: "")
        var parts: [String] = [category]
        if let member = asset.member {
            parts.append(member.name)
        }
        parts.append(asset.purchaseCurrency)
        return parts.joined(separator: " · ")
    }

    private func purchasedOnText(for asset: Asset) -> String {
        let date = asset.purchaseDate.formatted(.dateTime.year().month(.abbreviated).locale(locale))
        let template = String(localized: "asset.row.purchasedOn")
        return template.replacingOccurrences(of: "{date}", with: date)
    }

    private func assetCountFootnote(activeCount: Int) -> String {
        let template = String(localized: "asset.count.active")
        return template.replacingOccurrences(of: "{count}", with: String(activeCount))
    }

    private func itemCountFootnote(count: Int) -> String {
        let template = String(localized: "asset.section.itemCount")
        return template.replacingOccurrences(of: "{count}", with: String(count))
    }

    private func missingRatesMessage(_ currencies: [String]) -> String {
        let list = currencies.joined(separator: ", ")
        let template = String(localized: "overview.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: list)
    }

    // MARK: - Actions

    private func presentNewAsset() {
        guard let defaultMember = members.first else { return }
        // Create an unmanaged draft. We insert into the context only on
        // explicit save; dropping the sheet via swipe-down or click-outside
        // lets the draft deallocate, so no empty row is ever persisted.
        let draft = Asset(
            name: "",
            category: .realEstate,
            purchasePrice: 0,
            purchaseCurrency: homeCurrency,
            purchaseDate: .now,
            member: defaultMember
        )
        newAssetDraft = draft
    }
}

private struct AssetsToolbarModifier: ViewModifier {
    let showAdd: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.toolbar {
            if showAdd {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: action) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("asset.new.title"))
                }
            }
        }
        #endif
    }
}

/// Bundles the Assets screen's sheet + delete-confirmation modifiers so
/// `AssetsView.body` stays comfortably under the function-length budget.
private struct AssetsSheetsModifier: ViewModifier {
    @Binding var newAssetDraft: Asset?
    @Binding var editingAsset: Asset?
    @Binding var assetPendingDeletion: Asset?
    let context: ModelContext

    func body(content: Content) -> some View {
        content
            .sheet(item: $newAssetDraft) { draft in
                AssetFormView(asset: draft, isNew: true) { saved in
                    if saved { context.insert(draft) }
                    newAssetDraft = nil
                }
            }
            .sheet(item: $editingAsset) { asset in
                AssetFormView(asset: asset, isNew: false) { _ in
                    editingAsset = nil
                }
            }
            .confirmationDialog(
                Text("asset.delete.confirm.title"),
                isPresented: Binding(
                    get: { assetPendingDeletion != nil },
                    set: { if !$0 { assetPendingDeletion = nil } }
                ),
                presenting: assetPendingDeletion
            ) { asset in
                Button(role: .destructive) {
                    context.delete(asset)
                    assetPendingDeletion = nil
                } label: {
                    Text("common.action.delete")
                }
                Button(role: .cancel) { assetPendingDeletion = nil } label: { Text("common.action.cancel") }
            } message: { _ in
                Text("asset.delete.confirm.message")
            }
    }
}

#if DEBUG
#Preview("Assets · seeded") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        ScrollView {
            AssetsView()
                .padding(24)
        }
        .ambientBackground()
    }
    .modelContainer(PreviewSampleData.container())
}

#Preview("Assets · empty") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        ScrollView {
            AssetsView()
                .padding(24)
        }
        .ambientBackground()
    }
    .modelContainer(PreviewSampleData.container())
}
#endif
