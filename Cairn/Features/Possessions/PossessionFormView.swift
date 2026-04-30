import SwiftUI
import SwiftData

/// Create/edit form for a physical `Possession` (PRD §4.7, v1.1).
///
/// Caller pre-inserts the draft when creating so the form can bind directly
/// to the model. When the user cancels a new draft, `onFinish(false)` lets
/// the caller delete it.
struct PossessionFormView: View {
    @Bindable var possession: Possession
    let isNew: Bool
    var onFinish: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @Query(sort: \Member.createdAt) private var members: [Member]

    @State private var pendingError: DomainError?
    @State private var revalueEnabled: Bool = false
    @State private var soldEnabled: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                purchaseSection
                valuationSection
                saleSection
                ownerSection
                notesSection
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
            .keyboardDismissable()
            .navigationTitle(isNew ? "possession.new.title" : "possession.edit.title")
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
                        save()
                    } label: {
                        Text("common.action.save")
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                revalueEnabled = possession.currentValue != nil
                soldEnabled = possession.saleDate != nil
            }
        }
    }

    // MARK: - Sections

    private var basicsSection: some View {
        Section {
            TextField("possession.form.name", text: $possession.name)
                .autocorrectionDisabled()
            Picker(selection: Binding(
                get: { possession.category },
                set: { possession.category = $0 }
            )) {
                ForEach(PossessionCategory.allCases, id: \.self) { category in
                    Label {
                        Text(LocalizedStringKey(category.localizationKey))
                    } icon: {
                        Image(systemName: category.iconName)
                            .foregroundStyle(category.tint)
                    }
                    .tag(category)
                }
            } label: {
                Text("possession.form.category")
            }
            #if !os(macOS)
            .pickerStyle(.navigationLink)
            #endif
        } header: {
            Text("possession.form.section.basics")
        }
    }

    private var purchaseSection: some View {
        Section {
            DatePicker(
                selection: $possession.purchaseDate,
                displayedComponents: [.date]
            ) {
                Text("possession.form.purchaseDate")
            }
            DecimalField(
                labelKey: "possession.form.purchasePrice",
                value: $possession.purchasePrice
            )
            Picker(selection: $possession.purchaseCurrency) {
                Section("currency.picker.pinned") {
                    ForEach(CurrencyCatalog.pinned, id: \.self) { code in
                        PossessionCurrencyRow(code: code).tag(code)
                    }
                }
                Section("currency.picker.other") {
                    ForEach(CurrencyCatalog.rest, id: \.self) { code in
                        PossessionCurrencyRow(code: code).tag(code)
                    }
                }
            } label: {
                Text("currency.picker.title")
            }
            #if !os(macOS)
            .pickerStyle(.navigationLink)
            #endif
            .disabled(!isNew)
        } header: {
            Text("possession.form.section.purchase")
        } footer: {
            if !isNew {
                Text("possession.form.currency.immutable")
            }
        }
    }

    private var valuationSection: some View {
        Section {
            Toggle(isOn: $revalueEnabled) {
                Text("possession.form.revalue.enable")
            }
            .onChange(of: revalueEnabled) { _, newValue in
                if newValue {
                    if possession.currentValue == nil {
                        possession.currentValue = possession.purchasePrice
                        possession.currentValueUpdatedAt = .now
                    }
                } else {
                    PossessionService.updateCurrentValue(possession, to: nil)
                }
            }
            if revalueEnabled {
                DecimalField(
                    labelKey: "possession.form.currentValue",
                    value: Binding(
                        get: { possession.currentValue ?? 0 },
                        set: { newValue in
                            possession.currentValue = newValue
                            possession.currentValueUpdatedAt = .now
                        }
                    )
                )
                if let updated = possession.currentValueUpdatedAt {
                    Text(updatedAtFootnote(updated))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("possession.form.section.valuation")
        } footer: {
            Text("possession.form.section.valuation.hint")
        }
    }

    private var saleSection: some View {
        Section {
            Toggle(isOn: $soldEnabled) {
                Text("possession.form.sold.enable")
            }
            .onChange(of: soldEnabled) { _, newValue in
                if newValue {
                    if possession.saleDate == nil { possession.saleDate = .now }
                    if possession.salePrice == nil {
                        possession.salePrice = possession.currentValue ?? possession.purchasePrice
                    }
                } else {
                    PossessionService.markSold(possession, on: nil, price: nil)
                }
            }
            if soldEnabled {
                DatePicker(
                    selection: Binding(
                        get: { possession.saleDate ?? .now },
                        set: { possession.saleDate = $0 }
                    ),
                    displayedComponents: [.date]
                ) {
                    Text("possession.form.saleDate")
                }
                DecimalField(
                    labelKey: "possession.form.salePrice",
                    value: Binding(
                        get: { possession.salePrice ?? 0 },
                        set: { possession.salePrice = $0 }
                    )
                )
            }
        } header: {
            Text("possession.form.section.sale")
        }
    }

    private var ownerSection: some View {
        Section {
            Picker(selection: Binding(
                get: { possession.member?.id ?? members.first?.id ?? UUID() },
                set: { newID in
                    possession.member = members.first { $0.id == newID }
                }
            )) {
                ForEach(members, id: \.id) { member in
                    Text(verbatim: member.name).tag(member.id)
                }
            } label: {
                Text("possession.form.owner")
            }
            #if !os(macOS)
            .pickerStyle(.navigationLink)
            #endif
        } header: {
            Text("possession.form.section.owner")
        }
    }

    private var notesSection: some View {
        Section {
            TextField(
                "possession.form.note",
                text: Binding(
                    get: { possession.note ?? "" },
                    set: { possession.note = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
        } header: {
            Text("possession.form.note")
        }
    }

    // MARK: - Save

    private func save() {
        possession.name = trimmedName
        if trimmedName.isEmpty {
            pendingError = .missingRequiredField(fieldKey: "possession.form.name")
            return
        }
        if possession.member == nil, let first = members.first {
            possession.member = first
        }
        onFinish(true)
        dismiss()
    }

    private var trimmedName: String {
        possession.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updatedAtFootnote(_ date: Date) -> String {
        let template = String(localized: "possession.form.revalue.updatedAt")
        let formatted = date.formatted(.dateTime.year().month().day().locale(locale))
        return template.replacingOccurrences(of: "{date}", with: formatted)
    }
}

// MARK: - Small helpers

/// Decimal-friendly text field bound to a `Decimal` binding. Mirrors the
/// behaviour of the `SnapshotFormView`'s amount input so the UX feels
/// consistent across forms.
private struct DecimalField: View {
    let labelKey: LocalizedStringKey
    @Binding var value: Decimal

    var body: some View {
        TextField(
            labelKey,
            value: $value,
            format: .number.precision(.fractionLength(0))
        )
        #if !os(macOS)
        .keyboardType(.numberPad)
        #endif
    }
}

private struct PossessionCurrencyRow: View {
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

#if DEBUG
#Preview("PossessionForm · new") {
    let env = PreviewSampleData.seededContainer()
    let draft = Possession(
        name: "",
        category: .realEstate,
        purchasePrice: 0,
        purchaseCurrency: "USD",
        member: env.seed.alice
    )
    env.container.mainContext.insert(draft)
    return PossessionFormView(possession: draft, isNew: true)
        .modelContainer(env.container)
}
#endif
