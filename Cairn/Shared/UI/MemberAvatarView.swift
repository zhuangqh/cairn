import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import ImageIO
import UniformTypeIdentifiers

/// Circular avatar for a `Member`. Shows the uploaded photo when present,
/// otherwise falls back to a colored gradient bubble with the member's
/// initials — same palette the Members list used before photo support.
struct MemberAvatarView: View {
    let name: String
    let avatarData: Data?
    let seed: UUID
    var size: CGFloat = 44

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var tint: Color {
        let palette: [Color] = [.blue, .indigo, .teal, .pink, .orange, .purple, .green]
        let hash = abs(seed.hashValue)
        return palette[hash % palette.count]
    }

    var body: some View {
        ZStack {
            if let data = avatarData, let image = AvatarImage.decode(data: data) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(verbatim: initials)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Utilities for decoding / downscaling avatar images across platforms.
enum AvatarImage {
    /// Max edge (in pixels) we persist. Anything larger is downscaled on
    /// save to keep the SwiftData store + CloudKit payload small.
    static let maxPixelSize: CGFloat = 512

    /// Decode persisted `Data` into a SwiftUI `Image`. Returns nil when the
    /// bytes are not a recognizable image.
    static func decode(data: Data) -> Image? {
        #if canImport(UIKit)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #elseif canImport(AppKit)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        return nil
        #endif
    }

    /// Native pixel dimensions of the image, read from ImageIO metadata
    /// without fully decoding. Returns nil for unreadable data.
    static func pixelSize(data: Data) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
            let height = props[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    /// Downscale + recompress `data` as JPEG so we don't persist a 5 MB
    /// HEIC from the photo library. Falls back to the original bytes when
    /// the source cannot be decoded.
    static func normalize(data: Data) -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return data
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
            return data
        }
        let destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85
        ]
        CGImageDestinationAddImage(destination, thumb, destOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
    }
}
