import SwiftUI

/// Dismisses the on-screen keyboard. No-op on macOS where the system
/// already handles focus-out via Esc / clicking elsewhere.
@MainActor
func dismissKeyboard() {
    #if canImport(UIKit) && !os(watchOS)
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
    #endif
}

/// View modifier that gives every form / scroll-based screen a reliable
/// way to dismiss the iOS keyboard. The numeric keypad has no Return key,
/// so without an explicit affordance users get stuck once they tap into
/// an amount field.
///
/// Adds:
///   • Interactive swipe-to-dismiss on the enclosing scroll surface.
///   • Tap-anywhere-outside-an-input to dismiss.
///   • A "Done" button in the keyboard accessory toolbar.
///
/// On macOS this is effectively a no-op — the keyboard placement and
/// `scrollDismissesKeyboard` modifier are unavailable / unnecessary
/// there.
struct DismissKeyboardOnScrollModifier: ViewModifier {
    /// When `true`, also adds an accessory "Done" button above the
    /// keyboard. Disable on screens that already render their own
    /// bottom bar (e.g. a sticky footer with running totals) so the
    /// accessory doesn't visually collide with it.
    let showsToolbar: Bool

    func body(content: Content) -> some View {
        #if os(iOS) || os(visionOS)
        let base = content
            .scrollDismissesKeyboard(.interactively)
            // Tap anywhere outside a control to dismiss the keyboard.
            // `simultaneousGesture` lets the tap fire alongside any
            // underlying button / row tap, so list selection, toggles,
            // and form rows still work normally.
            .simultaneousGesture(
                TapGesture().onEnded { dismissKeyboard() }
            )
        if showsToolbar {
            base.toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        dismissKeyboard()
                    } label: {
                        Text("common.action.done")
                            .fontWeight(.semibold)
                    }
                }
            }
        } else {
            base
        }
        #else
        content
        #endif
    }
}

extension View {
    /// See `DismissKeyboardOnScrollModifier`. Apply to any `Form`,
    /// `ScrollView`, or `NavigationStack` that hosts text input so the
    /// iPhone keyboard can always be dismissed.
    ///
    /// - Parameter showsToolbar: pass `false` on screens with a sticky
    ///   bottom footer to avoid overlapping it with the accessory bar.
    func keyboardDismissable(showsToolbar: Bool = true) -> some View {
        modifier(DismissKeyboardOnScrollModifier(showsToolbar: showsToolbar))
    }
}
