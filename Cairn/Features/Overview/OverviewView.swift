import SwiftUI
import SwiftData

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
        NavigationStack {
            Group {
                if holdings.isEmpty {
                    ContentUnavailableView(
                        "overview.empty.title",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("overview.empty.hint")
                    )
                } else {
                    List {
                        totalSection
                        Section {
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
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        Section {
                            TrendChartView()
                        }
                        if !memberTotals.isEmpty {
                            membersSection
                        }
                    }
                }
            }
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
    }

    // MARK: - Sections

    private var totalSection: some View {
        Section {
            LabeledContent {
                Text(totals.amount, format: .currency(code: homeCurrency).locale(locale))
                    .font(.title2.monospacedDigit())
            } label: {
                Text("overview.netWorth")
            }

            if !totals.missingCurrencies.isEmpty {
                Label {
                    Text(missingRatesMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(.orange)
                .font(.footnote)
            }

            if let latest = rates.map(\.date).max() {
                Text(latestRatesFootnote(date: latest))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("overview.homeCurrency")
                Spacer()
                Text(verbatim: homeCurrency)
            }
        }
    }

    private var membersSection: some View {
        Section("overview.byMember") {
            ForEach(memberTotals) { entry in
                LabeledContent {
                    Text(entry.amount, format: .currency(code: homeCurrency).locale(locale))
                        .monospacedDigit()
                } label: {
                    Text(verbatim: entry.memberName)
                }
            }
        }
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
