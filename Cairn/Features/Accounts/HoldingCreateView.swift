import SwiftUI
import SwiftData

/// Dedicated create view for `Holding` so we can run uniqueness validation
/// through `HoldingService` before inserting into the context. Editing an
/// existing holding's currency is disallowed (PRD §3.3), so we use
/// `HoldingEditView` for edits.
struct HoldingCreateView: View {
    let account: Account
    var onClose: (DomainError?) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCurrency: String = "USD"
    @State private var label: String = ""
    @State private var pendingError: DomainError?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $selectedCurrency) {
                        Section("currency.picker.pinned") {
                            ForEach(CurrencyCatalog.pinned, id: \.self) { code in
                                CurrencyRow(code: code).tag(code)
                            }
                        }
                        Section("currency.picker.other") {
                            ForEach(CurrencyCatalog.rest, id: \.self) { code in
                                CurrencyRow(code: code).tag(code)
                            }
                        }
                    } label: {
                        Text("currency.picker.title")
                    }
                    #if !os(macOS)
                    .pickerStyle(.navigationLink)
                    #endif
                }

                Section {
                    TextField(
                        "holding.form.label",
                        text: $label
                    )
                    .autocorrectionDisabled()
                }

                if let pendingError {
                    Section {
                        Label {
                            Text(LocalizedStringKey(pendingError.localizationKey))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .keyboardDismissable()
            .navigationTitle("holding.new.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        onClose(nil)
                        dismiss()
                    } label: {
                        Text("common.action.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text("common.action.save")
                    }
                }
            }
        }
        .onAppear {
            if let first = existingCurrencies.first, first != selectedCurrency {
                // Nudge away from already-used codes so save is more likely to succeed.
                if let fallback = CurrencyCatalog.pinned.first(where: { !existingCurrencies.contains($0) }) {
                    selectedCurrency = fallback
                }
            }
        }
    }

    @MainActor
    private func save() {
        do {
            try HoldingService.create(
                currency: selectedCurrency,
                label: label.isEmpty ? nil : label,
                in: account,
                context: context
            )
            onClose(nil)
            dismiss()
        } catch let domainError as DomainError {
            pendingError = domainError
            onClose(domainError)
        } catch {
            // Unexpected; surface a generic required-field fallback.
            let wrapped = DomainError.missingRequiredField(fieldKey: "currency.picker.title")
            pendingError = wrapped
            onClose(wrapped)
        }
    }

    private var existingCurrencies: Set<String> {
        Set((account.holdings ?? []).filter { !$0.isArchived }.map(\.currency))
    }
}

private struct CurrencyRow: View {
    let code: String

    var body: some View {
        HStack {
            Text(verbatim: code)
                .font(.headline)
                .frame(width: 56, alignment: .leading)
            Text(verbatim: CurrencyCatalog.displayName(code))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let env = PreviewSampleData.seededContainer()
    return HoldingCreateView(account: env.seed.brokerage)
        .modelContainer(env.container)
}
