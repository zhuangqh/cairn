import SwiftUI

/// Snapshot history on the Assets financial tab: a year filter and one
/// row per captured portfolio snapshot, each pushing its detail page.
struct AssetsSnapshotsCard: View {
    let listing: AssetsView.SnapshotListing
    /// Whether any portfolio snapshot exists at all (before year filtering).
    let hasSnapshots: Bool
    @Binding var selectedYear: Int?
    let homeCurrency: String
    let locale: Locale

    var body: some View {
        LedgerSection(Text("assets.snapshots")) {
            if !listing.years.isEmpty {
                LedgerYearFilterMenu(selection: $selectedYear, years: listing.years)
            }
        } content: {
            if !hasSnapshots {
                VStack(alignment: .leading, spacing: 6) {
                    Text("assets.snapshots.empty.title")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.ink)
                    Text("assets.snapshots.empty.hint")
                        .font(.footnote)
                        .foregroundStyle(Color.ink2)
                }
                .padding(.vertical, 8)
            } else if listing.filtered.isEmpty {
                Text("assets.snapshots.filter.empty")
                    .font(.callout)
                    .foregroundStyle(Color.ink2)
                    .padding(.vertical, 8)
            } else {
                LedgerRows(data: listing.filtered) { snapshot in
                    let previous = listing.previous(for: snapshot)
                    NavigationLink(value: AssetsRoute.snapshot(snapshot, previous: previous)) {
                        AssetsSnapshotRow(
                            snapshot: snapshot,
                            previous: previous,
                            homeCurrency: homeCurrency,
                            locale: locale
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
