import SwiftUI
import SwiftData

/// Snapshot timeline for a single `Account`. Reached by tapping an account
/// card from the expanded member section on `MembersListView`. Hosts the
/// account's primary holding, lets the user add/edit snapshots, filter by
/// year, and edit the underlying account or holding from the toolbar.
struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var editingSnapshot: Snapshot?
    @State private var snapshotPendingDeletion: Snapshot?
    @State private var editingAccount = false
    @State private var editingHolding = false
    @State private var selectedYear: Int? = nil
    @State private var didInitFilter = false

    /// Shared ledger column widths (§5.5), scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .callout) private var balanceColumn: CGFloat = 112
    @ScaledMetric(relativeTo: .callout) private var changeColumn: CGFloat = 76

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerCard
                if let primary = primaryHolding {
                    LedgerSection(Text("account.detail.snapshots")) {
                        yearFilterMenu(for: primary)
                    } content: {
                        snapshotList(for: primary)
                    }
                    holdingsSection
                } else {
                    emptyHoldingCard
                }
            }
            .pageHorizontalPadding()
            .padding(.bottom, 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground()
        .navigationTitle(Text(verbatim: account.name.isEmpty ? " " : account.name))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { primeSelectedYear() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editingAccount = true
                    } label: {
                        Label {
                            Text("account.edit.title")
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    if primaryHolding != nil {
                        Button {
                            editingHolding = true
                        } label: {
                            Label {
                                Text("holding.edit.title")
                            } icon: {
                                Image(systemName: "tag")
                            }
                        }
                    }
                    if let primary = primaryHolding {
                        Button {
                            primary.isArchived.toggle()
                        } label: {
                            Label {
                                Text(primary.isArchived ? "common.action.unarchive" : "common.action.archive")
                            } icon: {
                                Image(systemName: primary.isArchived ? "tray.and.arrow.up" : "archivebox")
                            }
                        }
                    }
                } label: {
                    Label {
                        Text("common.action.more")
                    } icon: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(item: $editingSnapshot) { snapshot in
            if let primary = primaryHolding {
                SnapshotFormView(holding: primary, existing: snapshot)
            }
        }
        .sheet(isPresented: $editingAccount) {
            AccountFormView(account: account, isNew: false)
        }
        .sheet(isPresented: $editingHolding) {
            if let primary = primaryHolding {
                HoldingEditView(holding: primary)
            }
        }
        .alert(
            Text("snapshot.delete.confirm.title"),
            isPresented: Binding(
                get: { snapshotPendingDeletion != nil },
                set: { if !$0 { snapshotPendingDeletion = nil } }
            ),
            presenting: snapshotPendingDeletion
        ) { snapshot in
            Button(role: .destructive) {
                context.delete(snapshot)
                snapshotPendingDeletion = nil
            } label: {
                Text("common.action.delete")
            }
            Button(role: .cancel) {
                snapshotPendingDeletion = nil
            } label: {
                Text("common.action.cancel")
            }
        } message: { _ in
            Text("snapshot.delete.confirm.message")
        }
    }

    // MARK: - Hero

    /// Account identity row, then the primary holding's latest balance with
    /// its change from the previous record (§5.2).
    private var headerCard: some View {
        let primary = primaryHolding
        let sorted = primary.map(sortedSnapshots(for:)) ?? []
        let latest = sorted.first
        let previous = sorted.dropFirst().first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: LedgerMetrics.columnSpacing) {
                LedgerGlyphTile(systemName: account.kind.iconName, tint: account.kind.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(account.kind.localizationKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    Text(verbatim: identityLine)
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                }
                Spacer(minLength: 8)
                if account.isArchived {
                    Text("common.label.archived")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.ink2)
                }
                if let primary {
                    CurrencyChip(code: primary.currency)
                }
            }

            if let primary, let latest {
                LedgerHeroAmount(amount: latest.amount, code: primary.currency, locale: locale)
                    .padding(.top, 18)
                if let previous {
                    LedgerDeltaLine(
                        amount: latest.amount - previous.amount,
                        percent: previous.amount == 0
                            ? nil
                            : NSDecimalNumber(decimal: (latest.amount - previous.amount) / previous.amount).doubleValue,
                        code: primary.currency,
                        locale: locale,
                        caption: Text("dashboard.vsLastMonth")
                    )
                    .padding(.top, 10)
                }
                Text(latest.periodMonth, format: .dateTime.year().month(.wide).locale(locale))
                    .font(.footnote)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 3)
            }

            if let note = account.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.footnote)
                    .foregroundStyle(Color.ink2)
                    .padding(.top, 10)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Alice · Holds USD, EUR" — owner and active currencies.
    private var identityLine: String {
        var parts: [String] = []
        if let owner = account.member?.name, !owner.isEmpty { parts.append(owner) }
        if !activeCurrencies.isEmpty {
            let list = activeCurrencies.formatted(.list(type: .and).locale(locale))
            parts.append(String(localized: "account.detail.holds \(list)"))
        }
        return parts.joined(separator: " · ")
    }

    private var emptyHoldingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("holding.empty")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.ink)
            Text("holding.empty.hint")
                .font(.footnote)
                .foregroundStyle(Color.ink2)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { LedgerHairline() }
    }

    @ViewBuilder
    private func yearFilterMenu(for holding: Holding) -> some View {
        let years = availableYears(for: holding)
        if !years.isEmpty {
            Menu {
                Button {
                    selectedYear = nil
                } label: {
                    if selectedYear == nil {
                        Label("assets.snapshots.filter.allYears", systemImage: "checkmark")
                    } else {
                        Text("assets.snapshots.filter.allYears")
                    }
                }
                Divider()
                ForEach(years, id: \.self) { year in
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
                LedgerFilterLabel(
                    title: selectedYear.map(String.init) ?? String(localized: "assets.snapshots.filter.allYears")
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// Single-line three-column ledger (§5.5): month / balance / change,
    /// under a light header naming the unit. Balances keep the currency's
    /// minor-unit precision; shared column widths keep the columns aligned.
    @ViewBuilder
    private func snapshotList(for holding: Holding) -> some View {
        let snapshots = filteredSnapshots(for: holding)
        let all = sortedSnapshots(for: holding)
        if snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("snapshot.empty")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.ink)
                Text("snapshot.empty.hint")
                    .font(.footnote)
                    .foregroundStyle(Color.ink2)
            }
            .padding(.vertical, 8)
        } else {
            let digits = LedgerAmountFormat.minorUnits(for: holding.currency, locale: locale)
            let symbol = CurrencyAmountParts(0, code: holding.currency, locale: locale).symbol
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text("account.detail.column.month")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: String(localized: "account.detail.column.balance \(symbol)"))
                        .frame(minWidth: balanceColumn, alignment: .trailing)
                    Text("account.detail.column.change")
                        .frame(minWidth: changeColumn, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(Color.ink3)
                .lineLimit(1)
                .frame(minHeight: 30)
                .accessibilityHidden(true)

                ForEach(snapshots) { snapshot in
                    LedgerHairline()
                    ledgerRow(
                        snapshot,
                        previous: all.first { $0.periodMonth < snapshot.periodMonth },
                        digits: digits
                    )
                }
            }
        }
    }

    private func ledgerRow(_ snapshot: Snapshot, previous: Snapshot?, digits: Int) -> some View {
        let delta = previous.map { snapshot.amount - $0.amount }
        return HStack(spacing: 16) {
            // Abbreviated month at large text sizes so the column wraps on
            // a word boundary instead of hyphenating the month name.
            Text(
                snapshot.periodMonth,
                format: .dateTime.year()
                    .month(dynamicTypeSize >= .xxLarge ? .abbreviated : .wide)
                    .locale(locale)
            )
                .font(.callout)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(snapshot.amount, format: .number.precision(.fractionLength(digits)).locale(locale))
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.ink)
                .fixedSize()
                .frame(minWidth: balanceColumn, alignment: .trailing)
            Group {
                if let delta {
                    Text(verbatim: LedgerAmountFormat.signed(delta, digits: digits, locale: locale))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ChangeTone.color(for: delta, locale: locale))
                } else {
                    Text("account.detail.firstRecord")
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                }
            }
            .fixedSize()
            .frame(minWidth: changeColumn, alignment: .trailing)
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.vertical, 6)
        .frame(minHeight: LedgerMetrics.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            editingSnapshot = snapshot
        }
        .contextMenu {
            Button(role: .destructive) {
                snapshotPendingDeletion = snapshot
            } label: {
                Label {
                    Text("common.action.delete")
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Derived

    private var activeCurrencies: [String] {
        var seen: Set<String> = []
        return (account.holdings ?? [])
            .filter { !$0.isArchived }
            .map(\.currency)
            .filter { seen.insert($0).inserted }
    }

    private var primaryHolding: Holding? {
        let all = account.holdings ?? []
        return all.first { !$0.isArchived }
            ?? all.sorted { $0.createdAt < $1.createdAt }.first
    }

    private func sortedSnapshots(for holding: Holding) -> [Snapshot] {
        (holding.snapshots ?? []).sorted { $0.periodMonth > $1.periodMonth }
    }

    private func availableYears(for holding: Holding) -> [Int] {
        let calendar = Calendar.current
        let years = Set((holding.snapshots ?? []).map { calendar.component(.year, from: $0.periodMonth) })
        return years.sorted(by: >)
    }

    private func filteredSnapshots(for holding: Holding) -> [Snapshot] {
        let all = sortedSnapshots(for: holding)
        guard let selectedYear else { return all }
        let calendar = Calendar.current
        return all.filter { calendar.component(.year, from: $0.periodMonth) == selectedYear }
    }

    private func primeSelectedYear() {
        guard !didInitFilter else { return }
        didInitFilter = true
        guard let holding = primaryHolding,
              let latest = availableYears(for: holding).first else { return }
        selectedYear = latest
    }
}

extension AccountDetailView {
    // MARK: - Holdings

    /// Every active holding with its latest native balance.
    @ViewBuilder
    private var holdingsSection: some View {
        let active = (account.holdings ?? [])
            .filter { !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
        if !active.isEmpty {
            LedgerSection(Text("account.detail.holdings")) {
                LedgerRows(data: active, inset: LedgerMetrics.leadingColumn + LedgerMetrics.columnSpacing) { holding in
                    HStack(spacing: LedgerMetrics.columnSpacing) {
                        CurrencyCodeTag(code: holding.currency)
                            .frame(width: LedgerMetrics.leadingColumn, alignment: .leading)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: CurrencyCatalog.displayName(holding.currency, in: locale))
                                .font(.callout)
                                .foregroundStyle(Color.ink)
                            if let label = holding.label, !label.isEmpty {
                                Text(verbatim: label)
                                    .font(.caption)
                                    .foregroundStyle(Color.ink3)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 8)
                        if let latest = sortedSnapshots(for: holding).first {
                            Text(
                                latest.amount,
                                format: .currency(code: holding.currency)
                                    .precision(.fractionLength(0))
                                    .locale(locale)
                            )
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.ink)
                            .fixedSize()
                        } else {
                            Text(verbatim: "—")
                                .font(.callout)
                                .foregroundStyle(Color.ink3)
                        }
                    }
                    .frame(minHeight: LedgerMetrics.rowHeight)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

#if DEBUG
#Preview("AccountDetail · seeded") {
    let env = PreviewSampleData.seededContainer()
    let account = (env.seed.alice.accounts ?? []).first ?? Account(name: "Demo", kind: .cash, member: env.seed.alice)
    return NavigationStack {
        AccountDetailView(account: account)
    }
    .modelContainer(env.container)
}
#endif
