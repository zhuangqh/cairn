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
    var previous: PortfolioSnapshot? {
        explicitPrevious ?? resolvedPrevious
    }

    var body: some View {
        // Decode the captured entries once per render; hovering a row
        // re-runs `body`, and every section below reads them.
        let entries = snapshot.entries
        let priorEntries = previous?.entries
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderCard(snapshot: snapshot, capturedDate: capturedDate, totalDelta: totalDelta)
                if !entries.isEmpty {
                    HoldingsCard(
                        groups: memberGroups(entries: entries, priorEntries: priorEntries),
                        homeCurrency: snapshot.homeCurrency,
                        memberByName: memberByName,
                        hoveredEntryID: $hoveredEntryID,
                        convertedEntryID: $convertedEntryID
                    )
                }
                if let breakdown = PortfolioChangeBreakdown.compute(
                    current: entries,
                    prior: priorEntries,
                    homeCurrency: snapshot.homeCurrency
                ), breakdown.hasContent {
                    ChangeBreakdownCard(breakdown: breakdown, homeCurrency: snapshot.homeCurrency)
                }
            }
            .padding(.horizontal, Metrics.pageHorizontalInset)
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
                lockedRates: snapshot.lockedRatesForEdit,
                lockedBaseline: snapshot.lockedBaselineForEdit,
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
            isPresented: Binding(isPresent: $errorMessage)
        ) {
            Button { errorMessage = nil } label: { Text("common.action.done") }
        } message: {
            if let errorMessage { Text(verbatim: errorMessage) }
        }
    }

    private var titleText: String {
        snapshot.periodMonth.formatted(.dateTime.year().month(.wide).locale(locale).inUTC)
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
        let descriptor = FetchDescriptor<PortfolioSnapshot>(
            predicate: #Predicate { $0.periodMonth < month && $0.homeCurrency == currency }
        )
        resolvedPrevious = (try? context.fetch(descriptor))?
            .max { $0.periodMonth < $1.periodMonth }
    }

    /// Live members keyed by name, so each captured `memberName` can be
    /// matched to the current `Member` for avatar display. Best-effort:
    /// renamed members won't match.
    private var memberByName: [String: Member] {
        Dictionary(members.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Resolves each captured entry's holding to the live account's
    /// `kind`, so rows render the same glyph badge used elsewhere
    /// (account list, batch entry). Only entries without a captured
    /// `accountKind` consult this map, so the holdings fetch is skipped
    /// when every entry carries its kind.
    func accountKindByHolding(for entries: [PortfolioSnapshot.Entry]) -> [UUID: AccountKind] {
        let ids = Set(entries.filter { $0.accountKind == nil }.compactMap(\.holdingId))
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
}

#Preview {
    let env = PreviewSampleData.seededContainer()
    return NavigationStack {
        PortfolioSnapshotDetailView(snapshot: env.seed.latestPortfolioSnapshot)
    }
    .modelContainer(env.container)
    .environment(LocalizationService())
}
