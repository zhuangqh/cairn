import SwiftUI

/// Home-currency list pushed from Settings: pinned codes first, then the rest.
struct CurrencyPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("currency.picker.pinned") {
                ForEach(CurrencyCatalog.pinned, id: \.self) { code in
                    row(code)
                }
            }
            Section("currency.picker.other") {
                ForEach(CurrencyCatalog.rest, id: \.self) { code in
                    row(code)
                }
            }
        }
        .navigationTitle("currency.picker.title")
    }

    private func row(_ code: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: code)
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, alignment: .leading)
                Text(verbatim: CurrencyCatalog.displayName(code))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
