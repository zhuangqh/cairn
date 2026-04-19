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

    var body: some View {
        Group {
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
                    summaryCard
                    trendCard
                    categorizedCards
                    if !soldAssets.isEmpty {
                        soldCard
                    }
                }
            }
        }
        #if !os(macOS)
        // Plain "+" button in the nav-bar, matching the Accounts screen.
        // macOS keeps the inline button inside the summary card because the
        // nav-bar there already hosts the tab switcher.
        .toolbar {
            if !members.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: presentNewAsset) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("asset.new.title"))
                }
            }
        }
        #endif
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
            Button(role: .cancel) {
                assetPendingDeletion = nil
            } label: {
                Text("common.action.cancel")
            }
        } message: { _ in
            Text("asset.delete.confirm.message")
        }
    }

    // MARK: - Cards

    private var summaryCard: some View {
        let totals = AssetService.total(homeCurrency: homeCurrency, context: context)
        _ = rates.count  // keep the view reactive to FX updates
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
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
                Text(assetCountFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    /// Cumulative asset-purchase timeline. Styled to match `TrendChartView`
    /// in the Financial tab (same `glassCard` wrapper + minHeight) so the
    /// two tabs share a consistent visual rhythm.
    private var trendCard: some View {
        AssetTrendChartView()
            .glassCard()
    }

    @ViewBuilder
    private var categorizedCards: some View {
        ForEach(AssetCategory.allCases, id: \.self) { category in
            let bucket = activeAssets.filter { $0.category == category }
            if !bucket.isEmpty {
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

    private var soldCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private var activeAssets: [Asset] { assets.filter { !$0.isSold } }
    private var soldAssets: [Asset] { assets.filter { $0.isSold } }

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

    private var assetCountFootnote: String {
        let active = activeAssets.count
        let template = String(localized: "asset.count.active")
        return template.replacingOccurrences(of: "{count}", with: String(active))
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
