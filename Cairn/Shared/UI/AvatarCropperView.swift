import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import ImageIO
import UniformTypeIdentifiers

/// Simple square cropper. Shows the source image inside a fixed square
/// window; the user can pan and pinch-zoom to frame the subject, then
/// confirms the crop. Returns the cropped image as JPEG `Data` sized for
/// avatar storage.
struct AvatarCropperView: View {
    let sourceData: Data
    var onFinish: (Data?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private static let cropSide: CGFloat = 320

    private var image: Image? {
        AvatarImage.decode(data: sourceData)
    }

    private var imagePixelSize: CGSize? {
        AvatarImage.pixelSize(data: sourceData)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                cropCanvas
                    .frame(width: Self.cropSide, height: Self.cropSide)
                Text("member.form.avatar.cropper.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.9).ignoresSafeArea())
            .navigationTitle("member.form.avatar.cropper.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        onFinish(nil)
                        dismiss()
                    } label: {
                        Text("common.action.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let data = renderCroppedData()
                        onFinish(data)
                        dismiss()
                    } label: {
                        Text("common.action.save")
                    }
                    .disabled(image == nil)
                }
            }
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var cropCanvas: some View {
        ZStack {
            Color.black
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
            } else {
                Text("member.form.avatar.cropper.invalid")
                    .foregroundStyle(.secondary)
            }

            // Dimming mask + circular viewport.
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                var path = Path(rect)
                path.addEllipse(in: rect)
                ctx.fill(path, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                var stroke = Path()
                stroke.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
                ctx.stroke(stroke, with: .color(.white.opacity(0.8)), lineWidth: 2)
            }
            .allowsHitTesting(false)
        }
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    },
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(0.5, min(4.0, lastScale * value))
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
        )
    }

    // MARK: - Rendering

    /// Maps the user's pan/zoom of the fitted image into source-pixel
    /// coordinates, produces a centered square crop, and encodes it
    /// through `AvatarImage.normalize` so we keep a single ingestion
    /// pipeline (downscale + JPEG) for persisted avatars.
    private func renderCroppedData() -> Data? {
        guard let pixelSize = imagePixelSize, pixelSize.width > 0, pixelSize.height > 0 else {
            return AvatarImage.normalize(data: sourceData)
        }

        // `scaledToFit` in a square view: the image's longest edge matches
        // `cropSide`, and the other dimension is letter-boxed.
        let fitScale = min(Self.cropSide / pixelSize.width, Self.cropSide / pixelSize.height)
        let fittedWidth = pixelSize.width * fitScale
        let fittedHeight = pixelSize.height * fitScale
        let displayedWidth = fittedWidth * scale
        let displayedHeight = fittedHeight * scale

        // Crop window center in the displayed (view) coordinate space,
        // relative to the image's center after the user's offset.
        let centerX = -offset.width
        let centerY = -offset.height

        // Convert the crop window (Self.cropSide square, centered at 0,0
        // in the ZStack) into image-local (displayed) coordinates.
        let halfSide = Self.cropSide / 2
        let minX = centerX - halfSide
        let minY = centerY - halfSide

        // Map to source pixel space. `displayedWidth` spans the original
        // `pixelSize.width` pixels, so one displayed point = pixelSize.width / displayedWidth.
        let pxPerPointX = pixelSize.width / displayedWidth
        let pxPerPointY = pixelSize.height / displayedHeight

        // Top-left of displayed image is at (-displayedWidth/2, -displayedHeight/2).
        let imageLocalX = minX + displayedWidth / 2
        let imageLocalY = minY + displayedHeight / 2

        var cropRect = CGRect(
            x: imageLocalX * pxPerPointX,
            y: imageLocalY * pxPerPointY,
            width: Self.cropSide * pxPerPointX,
            height: Self.cropSide * pxPerPointY
        )
        // Clamp to image bounds.
        cropRect = cropRect.intersection(CGRect(origin: .zero, size: pixelSize))
        guard cropRect.width > 1, cropRect.height > 1 else {
            return AvatarImage.normalize(data: sourceData)
        }

        guard
            let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
            let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let cropped = cg.cropping(to: cropRect)
        else {
            return AvatarImage.normalize(data: sourceData)
        }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return AvatarImage.normalize(data: sourceData)
        }
        CGImageDestinationAddImage(
            destination,
            cropped,
            [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return AvatarImage.normalize(data: sourceData)
        }
        return AvatarImage.normalize(data: output as Data)
    }
}
