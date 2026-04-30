import SwiftUI

/// Root of the Accounts tab. Starts at the Members list so the user can pick
/// whose possessions to work with.
struct AccountsView: View {
    var body: some View {
        NavigationStack {
            MembersListView()
        }
    }
}

#Preview {
    AccountsView()
        .modelContainer(PreviewSampleData.container())
}
