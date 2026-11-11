import SwiftUI

extension Binding where Value == Bool {
    /// `true` while `optional` holds a value; setting `false` clears it.
    /// Drives `.alert(isPresented:)` from an optional pending item or message.
    init<Wrapped>(isPresent optional: Binding<Wrapped?>) {
        self = optional.isPresent
    }
}

private extension Optional {
    /// Presence flag behind `Binding(isPresent:)`; `true` leaves the value as is.
    var isPresent: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}
