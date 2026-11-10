import SwiftUI

/// 「陈列柜」 (DESIGN.md §5.10): one horizontally scrolling shelf of tiles —
/// 140pt wide, a 104pt image well on the `thumb` ground with the photo
/// multiplied into it, then the name and purchase price. Items run in
/// category order, most valuable first within each category.
struct PossessionShowcaseView: View {
    let shelves: [PossessionShowcaseLayout.Shelf]
    /// Native purchase price, shown under the name and read by VoiceOver.
    let priceText: (Possession) -> String
    let onSelect: (Possession) -> Void
    let onDelete: (Possession) -> Void

    @Environment(\.possessionInspector) private var inspector

    private static let tileWidth: CGFloat = 140
    private static let wellHeight: CGFloat = 104

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(shelves.flatMap(\.items), id: \.id) { possession in
                    figure(possession)
                }
            }
            .padding(.vertical, 2)
        }
        // `.hidden` still shows bars under "Always show scroll bars".
        .scrollIndicators(.never)
        .scrollClipDisabled()
    }

    // MARK: - Tile

    private func figure(_ possession: Possession) -> some View {
        let size = PossessionArtwork.shelfSize
        return Button {
            if let inspector {
                inspector.open(possession)
            } else {
                onSelect(possession)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.thumb)
                    PossessionArtwork(possession: possession, size: size)
                        .frame(width: size.width, height: size.height, alignment: .bottom)
                        .blendMode(.multiply)
                        .achievementInspectionSource(id: possession.id.uuidString)
                        // The inspection overlay carries the artwork while open.
                        .opacity(inspector?.inspectedID == possession.id ? 0 : 1)
                }
                .frame(width: Self.tileWidth, height: Self.wellHeight)
                Text(verbatim: possession.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 8)
                Text(verbatim: priceText(possession))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .frame(width: Self.tileWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: "\(possession.name) · \(priceText(possession))"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(possession.name), \(priceText(possession))"))
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button {
                onSelect(possession)
            } label: {
                Label { Text("common.action.edit") } icon: { Image(systemName: "pencil") }
            }
            Button(role: .destructive) {
                onDelete(possession)
            } label: {
                Label { Text("common.action.delete") } icon: { Image(systemName: "trash") }
            }
        }
    }
}
