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
    /// category, and compute the home-currency total once. Avoids the
    /// previous shape where `summaryCard`, `categorizedCards`, and the
    /// active/sold computed properties each re-iterated the full asset
    /// list (and `summaryCard` re-fetched + re-FX-converted everything on
    /// every body re-render).
    private struct Derivation {
        var totals: AssetService.Totals
        var active: [Asset]
        var sold: [Asset]
        var byCategory: [AssetCategory: [Asset]]
    }

    private func derive() -> Derivation {
        _ = rates.count // keep reactive to FX updates
        var active: [Asset] = []
        var sold: [Asset] = []
        var byCategory: [AssetCategory: [Asset]] = [:]
        active.reserveCapacity(assets.count)
        for asset in assets {
            if asset.isSold {
                sold.append(asset)
            } else {
                active.append(asset)
                byCategory[asset.category, default: []].append(asset)
            }
        }
        let totals = AssetService.total(homeCurrency: homeCurrency, context: context)
        return Derivation(totals: totals, active: active, sold: sold, byCategory: byCategory)
    }

    var body: some View {
        let derivation: Derivation = members.isEmpty || assets.isEmpty
            ? Derivation(totals: .init(amount: 0, missingCurrencies: []), active: [], sold: [], byCategory: [:])
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
        let totals = derivation.totals
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("asset.total.title")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: homeCurrency)
                    .font(.caption.monospaced().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            Text(
                totals.amount,
                format: .currency(code: homeCurrency)
                    .locale(locale)
                    .precision(.fractionLength(0))
            )
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
            if !totals.missingCurrencies.isEmpty {
                Label {
                    Text(missingRatesMessage(totals.missingCurrencies))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                .font(.footnote)
            }
            Text(assetCountFootnote(activeCount: derivation.active.count))
                .font(.caption)
                .foregroundStyle(.secondary)
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
                categorySection(category: category, assets: bucket)
            }
        }
    }

    private func categorySection(category: AssetCategory, assets: [Asset]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: category.iconName)
                    .foregroundStyle(category.tint)
                Text(LocalizedStringKey(category.localizationKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(verbatim: "\(assets.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
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
            HStack(spacing: 12) {
                GlyphBadge(
                    systemName: asset.iconName ?? asset.category.iconName,
                    tint: asset.category.tint
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: asset.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if let member = asset.member {
                            Text(verbatim: member.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(verbatim: asset.purchaseCurrency)
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                        if asset.isSold {
                            Text("asset.badge.sold")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else if asset.currentValue != nil {
                            Text("asset.badge.revalued")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(
                        valueForDisplay(asset),
                        format: .currency(code: asset.purchaseCurrency).locale(locale)
                    )
                    .monospacedDigit()
                    .font(.callout.weight(.semibold))
                    Text(valueLabel(for: asset))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
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

    private func valueForDisplay(_ asset: Asset) -> Decimal {
        if asset.isSold {
            return asset.salePrice ?? asset.purchasePrice
        }
        return asset.currentValue ?? asset.purchasePrice
    }

    private func valueLabel(for asset: Asset) -> LocalizedStringKey {
        if asset.isSold {
            return "asset.value.label.sale"
        }
        return asset.currentValue == nil ? "asset.value.label.purchase" : "asset.value.label.current"
    }

    private func assetCountFootnote(activeCount: Int) -> String {
        let template = String(localized: "asset.count.active")
        return template.replacingOccurrences(of: "{count}", with: String(activeCount))
    }

    private func missingRatesMessage(_ currencies: [String]) -> String {
        let list = currencies.joined(separator: ", ")
        let template = String(localized: "overview.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: list)
    }

    // MARK: - Actions

    private func presentNewAsset() {
        guard let defaultMember = members.first else { return }
        let draft = Asset(
            name: "",
            category: .realEstate,
            purchasePrice: 0,
            purchaseCurrency: homeCurrency,
            purchaseDate: .now,
            member: defaultMember
        )
        context.insert(draft)
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
                    if !saved { context.delete(draft) }
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
