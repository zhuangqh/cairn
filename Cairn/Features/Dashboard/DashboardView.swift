import SwiftUI
import SwiftData

/// Home screen of the app. Shows a hero net-worth card, allocation donut,
/// asset-category breakdown, and the most recent snapshot activity.
///
/// Styled with translucent glass cards against an ambient gradient, mirroring
/// Apple's Liquid Glass design language.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    // Query sentinels — touch .count in computed vars so @Query invalidates totals.
    @Query private var holdings: [Holding]
    @Query private var snapshots: [Snapshot]
    @Query private var rates: [FXRate]
    @Query private var members: [Member]

    @State private var isUpdating: Bool = false

    // MARK: - Computed

    private var totals: NetWorthCalculator.Totals {
        _ = holdings.count + snapshots.count + rates.count
        return NetWorthCalculator.total(homeCurrency: homeCurrency, context: context)
    }

    private var delta: Double? {
        _ = holdings.count + snapshots.count + rates.count
        return NetWorthCalculator.monthOverMonthDelta(
            homeCurrency: homeCurrency,
            context: context
        )
    }

    private var allocation: [NetWorthCalculator.KindTotal] {
        _ = holdings.count + snapshots.count + rates.count
        return NetWorthCalculator.totalsByKind(
            homeCurrency: homeCurrency,
            context: context
        )
    }

    private var activities: [NetWorthCalculator.Activity] {
        _ = snapshots.count
        return NetWorthCalculator.recentActivities(limit: 8, context: context)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                HStack(alignment: .top, spacing: 20) {
                    allocationCard
                        .frame(maxWidth: .infinity)
                    categoriesCard
                        .frame(maxWidth: .infinity)
                }
                activitiesCard
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(AppBackground())
        .navigationTitle("dashboard.title")
        .sheet(isPresented: $isUpdating) {
            BatchEntryView()
        }
    }

    // MARK: - Cards

    private var heroCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("dashboard.totalWealth")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.125)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.notionInkSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(
                        totals.amount,
                        format: .currency(code: homeCurrency).locale(locale)
                    )
                    .font(.system(size: 48, weight: .bold))
                    .tracking(-1.5)
                    .foregroundStyle(Color.notionInk)
                    .monospacedDigit()

                    if let delta {
                        deltaBadge(delta)
                    }
                }
            }
            Spacer()
            Button {
                isUpdating = true
            } label: {
                Label {
                    Text("dashboard.addAsset")
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(NotionPrimaryButtonStyle(size: .large))
            .disabled(holdings.isEmpty)
        }
        .glassCard(cornerRadius: 16, padding: 24)
    }

    private func deltaBadge(_ value: Double) -> some View {
        let positive = value >= 0
        let arrow = positive ? "arrow.up.right" : "arrow.down.right"
        let color: Color = positive ? .notionGreen : .notionOrange
        let badgeBg: Color = positive
            ? Color.notionGreen.opacity(0.12)
            : Color.notionOrange.opacity(0.12)
        return HStack(spacing: 4) {
            Image(systemName: arrow)
            Text(value, format: .percent.precision(.fractionLength(1)))
        }
        .font(.system(size: 12, weight: .semibold))
        .tracking(0.125)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeBg, in: Capsule())
    }

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("dashboard.portfolioAllocation")
                .font(.notionCardTitle)
                .tracking(-0.25)
                .foregroundStyle(Color.notionInk)
            AllocationDonutView(entries: allocation, homeCurrency: homeCurrency)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("dashboard.assetCategories")
                .font(.headline)
            let kinds = AccountKind.allCases
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(kinds, id: \.self) { kind in
                    categoryTile(for: kind)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func categoryTile(for kind: AccountKind) -> some View {
        let amount = allocation.first { $0.kind == kind }?.amount ?? 0
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind.tint.opacity(0.15))
                Image(systemName: kind.iconName)
                    .foregroundStyle(kind.tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(kind.localizationKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(
                    amount,
                    format: .currency(code: homeCurrency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.notionSurfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.notionBorder, lineWidth: 1)
        )
    }

    private var activitiesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("dashboard.recentActivities")
                .font(.headline)
            if activities.isEmpty {
                Text("dashboard.recentActivities.empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                        activityRow(activity)
                        if index < activities.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func activityRow(_ activity: NetWorthCalculator.Activity) -> some View {
        HStack(spacing: 16) {
            Text(activity.recordedAt.formatted(.dateTime.month(.abbreviated).day().locale(locale)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: activity.accountName.isEmpty ? activity.currency : activity.accountName)
                    .font(.callout.weight(.semibold))
                if !activity.memberName.isEmpty {
                    Text(verbatim: activity.memberName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(
                activity.amount,
                format: .currency(code: activity.currency).locale(locale)
            )
            .font(.callout.monospacedDigit().weight(.medium))
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    DashboardView()
        .modelContainer(PersistenceController.previewContainer())
}
