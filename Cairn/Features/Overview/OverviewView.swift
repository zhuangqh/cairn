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

    @State private var isRefreshing: Bool = false
    @State private var refreshError: String?
    @State private var isUpdating: Bool = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshRates() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label {
                            Text("overview.refreshRates")
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .alert(
            "overview.refresh.failure",
            isPresented: .init(
                get: { refreshError != nil },
                set: { if !$0 { refreshError = nil } }
            )
        ) {
            Button {
                refreshError = nil
            } label: {
                Text("common.action.done")
            }
        } message: {
            if let refreshError {
                Text(verbatim: refreshError)
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
                    Text("overview.updateThisMonth")
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

    private func refreshRates() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let quotes = Array(Set(holdings.map(\.currency))).filter { $0 != homeCurrency }
        guard !quotes.isEmpty else { return }

        do {
            try await FXService.refresh(base: homeCurrency, quotes: quotes, context: context)
        } catch {
            refreshError = error.localizedDescription
        }
    }
}

#Preview {
    OverviewView()
        .modelContainer(PersistenceController.previewContainer())
}
