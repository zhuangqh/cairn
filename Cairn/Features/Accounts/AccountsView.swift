import SwiftUI

struct AccountsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "common.placeholder.comingSoon",
                systemImage: "wallet.pass"
            )
            .navigationTitle("accounts.title")
        }
    }
}

#Preview {
    AccountsView()
        .modelContainer(PersistenceController.previewContainer())
}
