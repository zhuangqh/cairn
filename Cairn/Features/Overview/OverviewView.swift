import SwiftUI

struct OverviewView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "common.placeholder.comingSoon",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            .navigationTitle("overview.title")
        }
    }
}

#Preview {
    OverviewView()
        .modelContainer(PersistenceController.previewContainer())
}
