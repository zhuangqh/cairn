import SwiftUI
import SwiftData

/// Trend-focused view: net worth hero, multi-month chart, per-member breakdown.
/// Complements the Dashboard (which emphasizes allocation + activity).
struct OverviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query private var members: [Member]
    @Query private var holdings: [Holding]
    @Query private var snapshots: [Snapshot]
    @Query private var rates: [FXRate]
    @Query(sort: \PortfolioSnapshot.periodMonth, order: .reverse)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @State private var isUpdating: Bool = false
    @State private var selectedYear: Int? = nil

    private var totals: NetWorthCalculator.Totals {
        _ = snapshots.count + rates.count + holdings.count
        return NetWorthCalculator.total(homeCurrency: homeCurrency, context: context)
    }

    private var memberTotals: [NetWorthCalculator.MemberTotal] {
        _ = snapshots.count + rates.count + holdings.count + members.count
        return NetWorthCalculator.totalsByMember(homeCurrency: homeCurrency, context: context)
    }

    var body: some View {
        ScrollView {
            if holdings.isEmpty {
                ContentUnavailableView(
                    "overview.empty.title",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("overview.empty.hint")
                )
                .padding(.top, 64)
            } else {
                VStack(spacing: 20) {
                    heroCard
                    trendCard
                    if !memberTotals.isEmpty {
                        membersCard
                    }
                    snapshotsCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .ambientBackground()
        .navigationTitle("overview.title")
        .sheet(isPresented: $isUpdating) {
            BatchEntryView()
        }
        .onAppear {
            if selectedYear == nil, let latest = availableYears.first {
                selectedYear = latest
            }
        }
        .onChange(of: availableYears) { _, newYears in
            if let selected = selectedYear, !newYears.contains(selected) {
                selectedYear = newYears.first
            } else if selectedYear == nil {
                selectedYear = newYears.first
            }
        }
    }

    // MARK: - Cards

    private var heroCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("overview.netWorth")
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
                Text(totals.amount, format: .currency(code: homeCurrency).locale(locale))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()

                if !totals.missingCurrencies.isEmpty {
                    Label {
                        Text(missingRatesMessage)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                    .font(.footnote)
                }
                if let latest = rates.map(\.date).max(), totals.missingCurrencies.isEmpty {
                    Text(latestRatesFootnote(date: latest))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                isUpdating = true
            } label: {
                Label {
                    Text("overview.addSnapshot")
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .glassCard()
    }

    private var trendCard: some View {
        TrendChartView()
            .glassCard()
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("overview.byMember")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(memberTotals.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.18))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.accentColor)
                            )
                        Text(verbatim: entry.memberName)
                            .font(.callout)
                        Spacer()
                        Text(
                            entry.amount,
                            format: .currency(code: homeCurrency).locale(locale)
                        )
                        .monospacedDigit()
                        .font(.callout.weight(.semibold))
                    }
                    .padding(.vertical, 10)
                    if index < memberTotals.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var snapshotsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("overview.snapshots")
                    .font(.headline)
                Spacer()
                if !availableYears.isEmpty {
                    Menu {
                        Button {
                            selectedYear = nil
                        } label: {
                            if selectedYear == nil {
                                Label("overview.snapshots.filter.allYears", systemImage: "checkmark")
                            } else {
                                Text("overview.snapshots.filter.allYears")
                            }
                        }
                        Divider()
                        ForEach(availableYears, id: \.self) { year in
                            Button {
                                selectedYear = year
                            } label: {
                                if selectedYear == year {
                                    Label(String(year), systemImage: "checkmark")
                                } else {
                                    Text(verbatim: String(year))
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text(verbatim: selectedYear.map(String.init) ?? String(localized: "overview.snapshots.filter.allYears"))
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(.callout)
                }
                if !portfolioSnapshots.isEmpty {
                    Button {
                        isUpdating = true
                    } label: {
                        Label {
                            Text("overview.addSnapshot")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
            if portfolioSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("overview.snapshots.empty.title")
                        .font(.callout.weight(.medium))
                    Text("overview.snapshots.empty.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if filteredSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("overview.snapshots.filter.empty")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                        NavigationLink {
                            PortfolioSnapshotDetailView(snapshot: snapshot)
                        } label: {
                            snapshotRow(snapshot)
                        }
                        .buttonStyle(.plain)
                        if index < filteredSnapshots.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let years = Set(portfolioSnapshots.map { calendar.component(.year, from: $0.periodMonth) })
        return years.sorted(by: >)
    }

    private var filteredSnapshots: [PortfolioSnapshot] {
        guard let selectedYear else { return portfolioSnapshots }
        let calendar = Calendar.current
        return portfolioSnapshots.filter {
            calendar.component(.year, from: $0.periodMonth) == selectedYear
        }
    }

    private func snapshotRow(_ snapshot: PortfolioSnapshot) -> some View {
        HStack(spacing: 12) {
            GlyphBadge(systemName: "camera.aperture", tint: .accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: snapshot.periodMonth.formatted(.dateTime.year().month(.wide).locale(locale)))
                    .font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    Text(verbatim: snapshot.homeCurrency)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                    if let note = snapshot.note, !note.isEmpty {
                        Text(verbatim: note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(
                snapshot.totalAmount,
                format: .currency(code: snapshot.homeCurrency).locale(locale)
            )
            .monospacedDigit()
            .font(.callout.weight(.semibold))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var missingRatesMessage: String {
        let list = totals.missingCurrencies.joined(separator: ", ")
        let template = String(localized: "overview.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: list)
    }

    private func latestRatesFootnote(date: Date) -> String {
        let template = String(localized: "overview.ratesAsOf")
        let formatted = date.formatted(.dateTime.year().month().day().locale(locale))
        return template.replacingOccurrences(of: "{date}", with: formatted)
    }

    // MARK: - Actions
}

#Preview("Overview · seeded") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        OverviewView()
    }
    .modelContainer(PreviewSampleData.container())
}

#Preview("Overview · empty") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        OverviewView()
    }
    .modelContainer(PreviewSampleData.emptyContainer())
}
