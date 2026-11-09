import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// Photo area at the top of `PossessionFormView`. Picks an image (Photos and
/// camera on iOS; open panel or drag-and-drop on macOS), lifts the subject on
/// device via `PossessionPhotoService`, and writes the result to `photoData`.
/// While the picked photo is still in memory the user can flip between the
/// cutout and the original; saving the form confirms the choice.
struct PossessionPhotoWell: View {
    @Binding var photoData: Data?
    let category: PossessionCategory
    /// Mirrors the import state so the form can hold Save until it finishes.
    @Binding var isProcessing: Bool

    @State private var prepared: PossessionPhotoService.Prepared?
    @State private var usesCutout: Bool = true
    @State private var errorKey: LocalizedStringKey?
    @State private var isPickingPhoto: Bool = false
    @State private var pickedItem: PhotosPickerItem?
    #if os(iOS)
    @State private var isTakingPhoto: Bool = false
    #else
    @State private var isImportingFile: Bool = false
    @State private var isDropTargeted: Bool = false
    #endif

    var body: some View {
        VStack(spacing: 12) {
            preview
            if let prepared {
                if prepared.cutout != nil {
                    Picker(selection: $usesCutout) {
                        Text("possession.form.photo.mode.cutout").tag(true)
                        Text("possession.form.photo.mode.original").tag(false)
                    } label: {
                        Text("possession.form.photo")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                } else {
                    Text("possession.form.photo.noSubject")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            if let errorKey {
                Text(errorKey)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onChange(of: usesCutout) { _, _ in applyPrepared() }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task { await loadPicked(item) }
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $pickedItem, matching: .images)
        #if os(iOS)
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraCapture { data in
                isTakingPhoto = false
                if let data { Task { await process(data) } }
            }
            .ignoresSafeArea()
        }
        #else
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await processFile(at: url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await processFile(at: url) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        #endif
    }

    // MARK: - Pieces

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            shape.fill(category.tint.opacity(0.08))
            if isProcessing {
                ProgressView {
                    Text("possession.form.photo.processing")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let photoData, let photo = PossessionPhotoCache.photo(for: photoData) {
                if photo.isCutout {
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                } else {
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: category.iconName)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(category.tint)
                    #if os(macOS)
                    Text("possession.form.photo.dropHint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #endif
                }
            }
        }
        .frame(maxWidth: 320)
        .frame(height: 200)
        .clipShape(shape)
        #if os(macOS)
        .overlay {
            if isDropTargeted {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("possession.form.photo"))
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button {
                #if os(iOS)
                isPickingPhoto = true
                #else
                isImportingFile = true
                #endif
            } label: {
                Label {
                    Text(photoData == nil ? "possession.form.photo.choose" : "possession.form.photo.change")
                } icon: {
                    Image(systemName: "photo")
                }
            }
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    isTakingPhoto = true
                } label: {
                    Label {
                        Text("possession.form.photo.camera")
                    } icon: {
                        Image(systemName: "camera")
                    }
                }
            }
            #endif
            if photoData != nil {
                Button(role: .destructive) {
                    photoData = nil
                    prepared = nil
                    errorKey = nil
                } label: {
                    Label {
                        Text("possession.form.photo.remove")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        // Separate tap targets inside a single form row.
        .buttonStyle(.borderless)
        .disabled(isProcessing)
    }

    // MARK: - Import

    private func loadPicked(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorKey = "possession.form.photo.unreadable"
            return
        }
        await process(data)
    }

    #if os(macOS)
    private func processFile(at url: URL) async {
        let didStart = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if didStart { url.stopAccessingSecurityScopedResource() }
        guard let data else {
            errorKey = "possession.form.photo.unreadable"
            return
        }
        await process(data)
    }
    #endif

    private func process(_ data: Data) async {
        isProcessing = true
        errorKey = nil
        defer { isProcessing = false }
        do {
            prepared = try await PossessionPhotoService.prepare(data)
            usesCutout = true
            applyPrepared()
        } catch {
            errorKey = "possession.form.photo.unreadable"
        }
    }

    private func applyPrepared() {
        guard let prepared else { return }
        photoData = usesCutout ? (prepared.cutout ?? prepared.original) : prepared.original
    }
}

#if os(iOS)
/// Minimal camera capture returning JPEG data, or `nil` when cancelled.
private struct CameraCapture: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
#endif
