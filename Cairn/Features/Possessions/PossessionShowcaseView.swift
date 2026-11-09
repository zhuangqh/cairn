import SwiftUI

/// Figure-cabinet overview of active possessions: one glass shelf per
/// category, each item standing on the shelf as its photo cutout, a framed
/// original photo, or a placeholder figure when it has no photo yet.
/// Shelves scroll horizontally when their items don't fit; wide macOS
/// windows split the cabinet into two bays whose shelves line up per row.
struct PossessionShowcaseView<Header: View>: View {
    /// Nameplate across the top of the cabinet (the possessions total).
    @ViewBuilder let header: () -> Header
    let shelves: [PossessionShowcaseLayout.Shelf]
    /// Native purchase price, used for the hover tooltip and VoiceOver.
    let priceText: (Possession) -> String
    let onSelect: (Possession) -> Void
    let onDelete: (Possession) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.possessionInspector) private var inspector

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header()
                .padding(.horizontal, 20)
            bays
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cabinetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.frame, lineWidth: 1)
        }
    }

    // MARK: - Bays

    @ViewBuilder
    private var bays: some View {
        #if os(macOS)
        if shelves.count > 1 {
            ViewThatFits(in: .horizontal) {
                twoBays
                singleBay
            }
        } else {
            singleBay
        }
        #else
        singleBay
        #endif
    }

    private var singleBay: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(shelves) { shelf in
                shelfView(shelf)
            }
        }
    }

    #if os(macOS)
    /// Shelves paired row by row so both bays share each shelf line.
    private var twoBays: some View {
        let rows = stride(from: 0, to: shelves.count, by: 2).map { start in
            Array(shelves[start..<min(start + 2, shelves.count)])
        }
        return Grid(alignment: .bottomLeading, horizontalSpacing: 0, verticalSpacing: 20) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { shelf in
                        shelfView(shelf)
                            .frame(minWidth: 360, idealWidth: 360, maxWidth: .infinity)
                    }
                    if row.count == 1 {
                        Color.clear.frame(minWidth: 360, idealWidth: 360, maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
    }
    #endif

    // MARK: - Shelf

    private func shelfView(_ shelf: PossessionShowcaseLayout.Shelf) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringKey(shelf.category.localizationKey))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(palette.label)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            // Paired shelves share a row height: labels stay on top while
            // figures and the glass edge sit on a common baseline.
            Spacer(minLength: 0)
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 20) {
                    ForEach(shelf.items, id: \.id) { possession in
                        figure(possession)
                    }
                }
                .padding(.horizontal, 20)
            }
            // `.hidden` still shows bars under "Always show scroll bars".
            .scrollIndicators(.never)
            glassShelf
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Thin glass edge with a soft shadow falling onto the back wall.
    private var glassShelf: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.shelfEdge)
                .frame(height: 2)
            LinearGradient(colors: [palette.shelfShadow, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 10)
        }
        .padding(.horizontal, 12)
        .accessibilityHidden(true)
    }

    // MARK: - Figure

    private func figure(_ possession: Possession) -> some View {
        let size = PossessionArtwork.shelfSize
        return Button {
            if let inspector {
                inspector.open(possession)
            } else {
                onSelect(possession)
            }
        } label: {
            VStack(spacing: 8) {
                PossessionArtwork(possession: possession, size: size)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .achievementInspectionSource(id: possession.id.uuidString)
                    // The inspection overlay carries the artwork while open.
                    .opacity(inspector?.inspectedID == possession.id ? 0 : 1)
                    .background(alignment: .bottom) {
                        Ellipse()
                            .fill(palette.figureShadow)
                            .frame(width: size.width * 0.7, height: 8)
                            .blur(radius: 4)
                            .offset(y: 4)
                    }
                Text(verbatim: possession.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.plaqueText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(palette.plaque, in: Capsule())
                    .frame(maxWidth: size.width + 16)
            }
            .padding(.bottom, 6)
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

    // MARK: - Cabinet palette

    private var cabinetBackground: some View {
        ZStack {
            LinearGradient(colors: palette.wall, startPoint: .top, endPoint: .bottom)
            // Warm downlight from the top of the cabinet.
            RadialGradient(
                colors: [palette.light, .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
        }
    }

    private struct Palette {
        let wall: [Color]
        let light: Color
        let frame: Color
        let label: Color
        let shelfEdge: Color
        let shelfShadow: Color
        let figureShadow: Color
        let plaque: Color
        let plaqueText: Color
    }

    private var palette: Palette {
        if colorScheme == .dark {
            return Palette(
                wall: [Color(white: 0.15), Color(white: 0.08)],
                light: Color(red: 1, green: 0.90, blue: 0.75).opacity(0.16),
                frame: .white.opacity(0.08),
                label: .white.opacity(0.55),
                shelfEdge: .white.opacity(0.22),
                shelfShadow: .black.opacity(0.35),
                figureShadow: .black.opacity(0.55),
                plaque: .white.opacity(0.08),
                plaqueText: .white.opacity(0.75)
            )
        }
        return Palette(
            wall: [Color(white: 0.985), Color(red: 0.92, green: 0.92, blue: 0.90)],
            light: Color(red: 1, green: 0.93, blue: 0.80).opacity(0.55),
            frame: .black.opacity(0.06),
            label: .black.opacity(0.45),
            shelfEdge: .white,
            shelfShadow: .black.opacity(0.10),
            figureShadow: .black.opacity(0.22),
            plaque: .black.opacity(0.05),
            plaqueText: .black.opacity(0.65)
        )
    }
}
