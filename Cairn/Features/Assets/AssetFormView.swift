import SwiftUI
import SwiftData

/// Create/edit form for a physical `Asset` (PRD §4.7, v1.1).
///
/// Caller pre-inserts the draft when creating so the form can bind directly
/// to the model. When the user cancels a new draft, `onFinish(false)` lets
/// the caller delete it.
struct AssetFormView: View {
    @Bindable var asset: Asset
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
            .navigationTitle(isNew ? "asset.new.title" : "asset.edit.title")
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
                revalueEnabled = asset.currentValue != nil
                soldEnabled = asset.saleDate != nil
            }
        }
    }

    // MARK: - Sections

    private var basicsSection: some View {
        Section {
            TextField("asset.form.name", text: $asset.name)
                .autocorrectionDisabled()
            Picker(selection: Binding(
                get: { asset.category },
                set: { asset.category = $0 }
            )) {
                ForEach(AssetCategory.allCases, id: \.self) { category in
                    Label {
                        Text(LocalizedStringKey(category.localizationKey))
                    } icon: {
                        Image(systemName: category.iconName)
                            .foregroundStyle(category.tint)
                    }
                    .tag(category)
                }
            } label: {
                Text("asset.form.category")
            }
            #if !os(macOS)
            .pickerStyle(.navigationLink)
            #endif
        } header: {
            Text("asset.form.section.basics")
        }
    }

    private var purchaseSection: some View {
        Section {
            DatePicker(
                selection: $asset.purchaseDate,
                displayedComponents: [.date]
            ) {
                Text("asset.form.purchaseDate")
            }
            DecimalField(
                labelKey: "asset.form.purchasePrice",
                value: $asset.purchasePrice
            )
            Picker(selection: $asset.purchaseCurrency) {
                Section("currency.picker.pinned") {
                    ForEach(CurrencyCatalog.pinned, id: \.self) { code in
                        AssetCurrencyRow(code: code).tag(code)
                    }
                }
                Section("currency.picker.other") {
                    ForEach(CurrencyCatalog.rest, id: \.self) { code in
                        AssetCurrencyRow(code: code).tag(code)
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
            Text("asset.form.section.purchase")
        } footer: {
            if !isNew {
                Text("asset.form.currency.immutable")
            }
        }
    }

    private var valuationSection: some View {
        Section {
            Toggle(isOn: $revalueEnabled) {
                Text("asset.form.revalue.enable")
            }
            .onChange(of: revalueEnabled) { _, newValue in
                if newValue {
                    if asset.currentValue == nil {
                        asset.currentValue = asset.purchasePrice
                        asset.currentValueUpdatedAt = .now
                    }
                } else {
                    AssetService.updateCurrentValue(asset, to: nil)
                }
            }
            if revalueEnabled {
                DecimalField(
                    labelKey: "asset.form.currentValue",
                    value: Binding(
                        get: { asset.currentValue ?? 0 },
                        set: { newValue in
                            asset.currentValue = newValue
                            asset.currentValueUpdatedAt = .now
                        }
                    )
                )
                if let updated = asset.currentValueUpdatedAt {
                    Text(updatedAtFootnote(updated))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("asset.form.section.valuation")
        } footer: {
            Text("asset.form.section.valuation.hint")
        }
    }

    private var saleSection: some View {
        Section {
            Toggle(isOn: $soldEnabled) {
                Text("asset.form.sold.enable")
            }
            .onChange(of: soldEnabled) { _, newValue in
                if newValue {
                    if asset.saleDate == nil { asset.saleDate = .now }
                    if asset.salePrice == nil {
                        asset.salePrice = asset.currentValue ?? asset.purchasePrice
                    }
                } else {
                    AssetService.markSold(asset, on: nil, price: nil)
                }
            }
            if soldEnabled {
                DatePicker(
                    selection: Binding(
                        get: { asset.saleDate ?? .now },
                        set: { asset.saleDate = $0 }
                    ),
                    displayedComponents: [.date]
                ) {
                    Text("asset.form.saleDate")
                }
                DecimalField(
                    labelKey: "asset.form.salePrice",
                    value: Binding(
                        get: { asset.salePrice ?? 0 },
                        set: { asset.salePrice = $0 }
                    )
                )
            }
        } header: {
            Text("asset.form.section.sale")
        }
    }

    private var ownerSection: some View {
        Section {
            Picker(selection: Binding(
                get: { asset.member?.id ?? members.first?.id ?? UUID() },
                set: { newID in
                    asset.member = members.first { $0.id == newID }
                }
            )) {
                ForEach(members, id: \.id) { member in
                    Text(verbatim: member.name).tag(member.id)
                }
            } label: {
                Text("asset.form.owner")
            }
            #if !os(macOS)
            .pickerStyle(.navigationLink)
            #endif
        } header: {
            Text("asset.form.section.owner")
        }
    }

    private var notesSection: some View {
        Section {
            TextField(
                "asset.form.note",
                text: Binding(
                    get: { asset.note ?? "" },
                    set: { asset.note = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
        } header: {
            Text("asset.form.note")
        }
    }

    // MARK: - Save

    private func save() {
        asset.name = trimmedName
        if trimmedName.isEmpty {
            pendingError = .missingRequiredField(fieldKey: "asset.form.name")
            return
        }
        if asset.member == nil, let first = members.first {
            asset.member = first
        }
        onFinish(true)
        dismiss()
    }

    private var trimmedName: String {
        asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updatedAtFootnote(_ date: Date) -> String {
        let template = String(localized: "asset.form.revalue.updatedAt")
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
            format: .number.precision(.fractionLength(0...2))
        )
        #if !os(macOS)
        .keyboardType(.decimalPad)
        #endif
    }
}

private struct AssetCurrencyRow: View {
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
#Preview("AssetForm · new") {
    let env = PreviewSampleData.seededContainer()
    let draft = Asset(
        name: "",
        category: .realEstate,
        purchasePrice: 0,
        purchaseCurrency: "USD",
        member: env.seed.alice
    )
    env.container.mainContext.insert(draft)
    return AssetFormView(asset: draft, isNew: true)
        .modelContainer(env.container)
}
#endif
