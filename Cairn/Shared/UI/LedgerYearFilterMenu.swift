import SwiftUI

/// Section-header year filter shared by the snapshot ledgers: "All years"
/// plus one entry per year, the current choice checkmarked, shown as a
/// `LedgerFilterLabel`. `nil` selects all years.
struct LedgerYearFilterMenu: View {
    @Environment(LocalizationService.self) private var localization
    @Binding var selection: Int?
    /// Years to offer, newest first.
    let years: [Int]

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label("assets.snapshots.filter.allYears", systemImage: "checkmark")
                } else {
                    Text("assets.snapshots.filter.allYears")
                }
            }
            Divider()
            ForEach(years, id: \.self) { year in
                Button {
                    selection = year
                } label: {
                    if selection == year {
                        Label(String(year), systemImage: "checkmark")
                    } else {
                        Text(verbatim: String(year))
                    }
                }
            }
        } label: {
            LedgerFilterLabel(
                title: selection.map(String.init) ?? String(localized: "assets.snapshots.filter.allYears", bundle: localization.bundle)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Distinct years of `dates` in UTC (the time zone of snapshot keys), newest first.
    static func years(of dates: some Sequence<Date>) -> [Int] {
        let calendar = Snapshot.utcCalendar
        return Set(dates.map { calendar.component(.year, from: $0) }).sorted(by: >)
    }

    /// `items` whose `date` falls in `year` (UTC); all of them
    /// when `year` is `nil`. Order is preserved.
    static func filter<Item>(_ items: [Item], year: Int?, date: (Item) -> Date) -> [Item] {
        guard let year else { return items }
        let calendar = Snapshot.utcCalendar
        return items.filter { calendar.component(.year, from: date($0)) == year }
    }
}
