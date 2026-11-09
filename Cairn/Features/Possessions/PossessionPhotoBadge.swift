import SwiftUI
import ImageIO

/// Decoded possession photo plus whether it is a transparent cutout (drawn
/// whole) or an opaque original (cropped to fill its frame).
struct DecodedPossessionPhoto {
    let image: CGImage
    let isCutout: Bool
}

/// Decodes stored photo bytes once per distinct payload so list rows and the
/// form don't re-decode a ~1024px image on every render.
@MainActor
enum PossessionPhotoCache {
    private final class Box {
        let photo: DecodedPossessionPhoto
        init(_ photo: DecodedPossessionPhoto) { self.photo = photo }
    }

    private static let cache: NSCache<NSData, Box> = {
        let cache = NSCache<NSData, Box>()
        cache.countLimit = 128
        return cache
    }()

    static func photo(for data: Data) -> DecodedPossessionPhoto? {
        let key = data as NSData
        if let hit = cache.object(forKey: key) { return hit.photo }
        guard let source = CGImageSourceCreateWithData(key, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let alpha = image.alphaInfo
        let hasAlpha = !(alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast)
        let photo = DecodedPossessionPhoto(image: image, isCutout: hasAlpha)
        cache.setObject(Box(photo), forKey: key)
        return photo
    }
}

/// Square leading mark for a possession: its photo on the category's tinted
/// tile, falling back to the category glyph when there is no photo.
struct PossessionPhotoBadge: View {
    let photoData: Data?
    let systemName: String
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        if let photoData, let photo = PossessionPhotoCache.photo(for: photoData) {
            let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            ZStack {
                shape.fill(tint.opacity(0.10))
                if photo.isCutout {
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.08)
                } else {
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
        } else {
            GlyphBadge(systemName: systemName, tint: tint, size: size)
        }
    }
}
