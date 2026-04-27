import SwiftUI
import SwiftData
import PhotosUI

/// Edit form for a `Member`. When `isNew` is true, the caller is expected to
/// have already inserted an empty draft into the context; cancelling the form
/// invokes `onFinish(false)` so the caller can delete the draft.
struct MemberFormView: View {
    @Bindable var member: Member
    let isNew: Bool
    var onFinish: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingPhoto: Bool = false
    @State private var cropperSource: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        MemberAvatarView(
                            name: member.name,
                            avatarData: member.avatarData,
                            seed: member.id,
                            size: 72
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(
                                selection: $photoItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label {
                                    Text(member.avatarData == nil
                                         ? "member.form.avatar.choose"
                                         : "member.form.avatar.change")
                                } icon: {
                                    Image(systemName: "photo")
                                }
                            }
                            .disabled(isImportingPhoto)

                            if member.avatarData != nil {
                                Button(role: .destructive) {
                                    member.avatarData = nil
                                    photoItem = nil
                                } label: {
                                    Label {
                                        Text("member.form.avatar.remove")
                                    } icon: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                } header: {
                    Text("member.form.avatar")
                }

                Section {
                    TextField("member.form.name", text: $member.name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("member.form.name")
                }
            }
            .formStyle(.grouped)
            .glassListStyle()
            .keyboardDismissable()
            .navigationTitle(isNew ? "member.new.title" : "member.edit.title")
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
                        onFinish(true)
                        dismiss()
                    } label: {
                        Text("common.action.save")
                    }
                    .disabled(trimmedName.isEmpty || isImportingPhoto)
                }
            }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                importPhoto(newValue)
            }
            .sheet(item: Binding(
                get: { cropperSource.map { CropSource(data: $0) } },
                set: { cropperSource = $0?.data }
            )) { source in
                AvatarCropperView(sourceData: source.data) { cropped in
                    if let cropped {
                        member.avatarData = cropped
                    }
                    cropperSource = nil
                }
            }
        }
    }

    private struct CropSource: Identifiable {
        let data: Data
        var id: Int { data.hashValue }
    }

    private var trimmedName: String {
        member.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        isImportingPhoto = true
        Task { @MainActor in
            defer { isImportingPhoto = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                return
            }
            // Present the cropper on the raw picked data; cropping will
            // also run the normalize pipeline before persisting.
            cropperSource = data
            photoItem = nil
        }
    }
}

#Preview("MemberForm · new") {
    let env = PreviewSampleData.seededContainer()
    let draft = Member(name: "")
    env.container.mainContext.insert(draft)
    return MemberFormView(member: draft, isNew: true)
        .modelContainer(env.container)
}

#Preview("MemberForm · edit") {
    let env = PreviewSampleData.seededContainer()
    return MemberFormView(member: env.seed.alice, isNew: false)
        .modelContainer(env.container)
}
