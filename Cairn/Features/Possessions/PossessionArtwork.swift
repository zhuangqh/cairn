import SwiftUI

/// A possession as it stands in the showcase: its cutout, its original photo
/// as a framed print, or a category glyph on a pedestal when there is no
/// photo. Shared by the shelves and the inspection overlay; everything is
/// proportional to `size`, so the overlay's copy scaled down to the shelf
/// box is pixel-identical to the figure it hands back to.
struct PossessionArtwork: View {
    /// The shelf figure box. The inspection overlay keeps this aspect ratio
    /// so its source-to-centre scale maps one box onto the other exactly.
    static let shelfSize = CGSize(width: 104, height: 80)

    let possession: Possession
    let size: CGSize

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let data = possession.photoData, let photo = PossessionPhotoCache.photo(for: data) {
            if photo.isCutout {
                Image(decorative: photo.image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                // An original photo stands as a framed print that fits the
                // box border included; overflow was clipped on the shelf but
                // not in the overlay, which made the hand-back jump. Border
                // and corners scale with the box (4 / 3 / 5 pt on the shelf).
                let unit = size.height / Self.shelfSize.height
                let photoHeight = size.height - 8 * unit
                Image(decorative: photo.image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: photoHeight * 0.75, height: photoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 3 * unit, style: .continuous))
                    .padding(4 * unit)
                    .background(printBorder, in: RoundedRectangle(cornerRadius: 5 * unit, style: .continuous))
            }
        } else {
            placeholder
        }
    }

    private var printBorder: Color {
        colorScheme == .dark ? Color(white: 0.92) : .white
    }

    private var placeholder: some View {
        let tint = possession.category.tint
        let height = size.height
        return VStack(spacing: 0) {
            Image(systemName: possession.iconName ?? possession.category.iconName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint.opacity(0.75))
                .frame(maxHeight: height * 0.55)
                .padding(.bottom, height * 0.06)
            Capsule()
                .fill(tint.opacity(0.22))
                .frame(width: height * 0.7, height: height * 0.1)
            Rectangle()
                .fill(tint.opacity(0.14))
                .frame(width: height * 0.6, height: height * 0.12)
        }
    }
}
