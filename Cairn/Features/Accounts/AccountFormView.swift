import SwiftUI
import SwiftData

/// Create/edit form for an `Account`. Caller pre-inserts the draft when creating.
struct AccountFormView: View {
    @Bindable var account: Account
    let isNew: Bool
    var onFinish: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var initialCurrency: String = "USD"
    @State private var pendingError: DomainError?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("account.form.name", text: $account.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("account.form.name")
                }
                Section {
                    Picker(selection: Binding(
                        get: { account.kind },
                        set: { account.kind = $0 }
                    )) {
                        ForEach(AccountKind.allCases, id: \.self) { kind in
                            Label {
                                Text(LocalizedStringKey(kind.localizationKey))
                            } icon: {
                                Image(systemName: kind.iconName)
                                    .foregroundStyle(kind.tint)
                            }
                            .tag(kind)
                        }
                    } label: {
                        Text("account.form.kind")
                    }
                    #if !os(macOS)
                    .pickerStyle(.navigationLink)
                    #endif
                } header: {
                    Text("account.form.kind")
                }
                if isNew {
                    Section {
                        Picker(selection: $initialCurrency) {
                            Section("currency.picker.pinned") {
                                ForEach(CurrencyCatalog.pinned, id: \.self) { code in
                                    CurrencyPickerRow(code: code).tag(code)
                                }
                            }
                            Section("currency.picker.other") {
                                ForEach(CurrencyCatalog.rest, id: \.self) { code in
                                    CurrencyPickerRow(code: code).tag(code)
                                }
                            }
                        } label: {
                            Text("currency.picker.title")
                        }
                        #if !os(macOS)
                        .pickerStyle(.navigationLink)
                        #endif
                    } header: {
                        Text("currency.picker.title")
                    }
                }
                Section {
                    TextField(
                        "account.form.note",
                        text: Binding(
                            get: { account.note ?? "" },
                            set: { account.note = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                } header: {
                    Text("account.form.note")
                }

                if let pendingError {
                    Section {
                        Label {
                            Text(LocalizedStringKey(pendingError.localizationKey))
                                .foregroundStyle(.red)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .glassListStyle()
            .navigationTitle(isNew ? "account.new.title" : "account.edit.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        onFinish(false)
                        dismiss()
                    } label: {
                        Text("common.action.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if isNew {
                            do {
                                try HoldingService.create(
                                    currency: initialCurrency,
                                    in: account,
                                    context: context
                                )
                            } catch let domainError as DomainError {
                                pendingError = domainError
                                return
                            } catch {
                                pendingError = .missingRequiredField(fieldKey: "currency.picker.title")
                                return
                            }
                        }
                        onFinish(true)
                        dismiss()
                    } label: {
                        Text("common.action.save")
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        account.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CurrencyPickerRow: View {
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
