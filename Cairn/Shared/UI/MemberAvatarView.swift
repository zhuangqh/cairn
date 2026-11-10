import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import ImageIO
import UniformTypeIdentifiers

/// Circular avatar for a `Member`. Shows the uploaded photo when present,
/// otherwise falls back to a low-saturation tinted disc with the member's
/// initials in a deeper shade of the same hue (DESIGN.md §2).
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

    /// Muted (fill, letter) pairs of equal lightness. Indexed by a stable
    /// digest of the member id so a member keeps its tone across launches
    /// (`hashValue` is reseeded per process).
    private static let palette: [(fill: Color, letter: Color)] = [
        (Color(light: Color(hex: 0xDCE5DF), dark: Color(hex: 0x2A3A32)), .accent),
        (Color(light: Color(hex: 0xEAE5DA), dark: Color(hex: 0x3A352B)),
         Color(light: Color(hex: 0x6B604B), dark: Color(hex: 0xD4C8AE))),
        (Color(light: Color(hex: 0xDFE3E8), dark: Color(hex: 0x2C333A)),
         Color(light: Color(hex: 0x4F5D6A), dark: Color(hex: 0xBAC6D2))),
        (Color(light: Color(hex: 0xE8E0DD), dark: Color(hex: 0x3A2F2C)),
         Color(light: Color(hex: 0x6E5852), dark: Color(hex: 0xD9C2BB)))
    ]

    private var tone: (fill: Color, letter: Color) {
        let digest = withUnsafeBytes(of: seed.uuid) { $0.reduce(0) { $0 &+ Int($1) } }
        return Self.palette[digest % Self.palette.count]
    }

    var body: some View {
        ZStack {
            if let data = avatarData, let image = AvatarImage.decode(data: data) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(tone.fill)
                Text(verbatim: initials)
                    .font(.system(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(tone.letter)
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
