import SwiftUI
import SwiftData

/// Bundles the Possessions screen's sheet + delete-confirmation modifiers so
/// `PossessionsView.body` stays comfortably under the function-length budget.
struct PossessionsSheetsModifier: ViewModifier {
    @Binding var newPossessionDraft: Possession?
    @Binding var newPossessionSaved: Bool
    @Binding var pendingNewPossession: Possession?
    @Binding var editingPossession: Possession?
    @Binding var possessionPendingDeletion: Possession?
    let context: ModelContext

    func body(content: Content) -> some View {
        content
            .sheet(
                item: $newPossessionDraft,
                onDismiss: {
                    // Covers both Cancel taps and interactive swipe-down
                    // dismissal on iOS. By the time `onDismiss` fires the
                    // sheet's `item` binding is already nil, so we use
                    // `pendingNewPossession` to reach the draft we inserted.
                    if !newPossessionSaved, let draft = pendingNewPossession {
                        context.delete(draft)
                    }
                    pendingNewPossession = nil
                    newPossessionSaved = false
                }
            ) { draft in
                PossessionFormView(possession: draft, isNew: true) { saved in
                    newPossessionSaved = saved
                }
            }
            .sheet(item: $editingPossession) { possession in
                PossessionFormView(possession: possession, isNew: false) { _ in
                    editingPossession = nil
                }
            }
            // Use `.alert` rather than `.confirmationDialog` here: when
            // triggered from a row's context menu inside a `LazyVStack`,
            // a confirmation dialog on iOS can race with the menu's
            // dismissal animation (requiring a second tap) and anchors
            // its popover oddly on iPad. An alert is system-modal and
            // centered, which avoids both issues.
            .alert(
                Text("possession.delete.confirm.title"),
                isPresented: Binding(
                    get: { possessionPendingDeletion != nil },
                    set: { if !$0 { possessionPendingDeletion = nil } }
                ),
                presenting: possessionPendingDeletion
            ) { possession in
                Button(role: .destructive) {
                    context.delete(possession)
                    possessionPendingDeletion = nil
                } label: {
                    Text("common.action.delete")
                }
                Button(role: .cancel) { possessionPendingDeletion = nil } label: { Text("common.action.cancel") }
            } message: { _ in
                Text("possession.delete.confirm.message")
            }
    }
}
