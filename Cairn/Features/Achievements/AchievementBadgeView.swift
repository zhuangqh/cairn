import SwiftUI

/// A Cairn achievement rendered as carved stone. Motion is deliberately
/// controlled by the owning transition so badges never rotate on their own.
struct AchievementBadgeView: View {
    let family: AchievementFamily
    let stageKey: String
    var size: CGFloat = 72
    var rotationY: Double = 0
    var crackIntensity: Double = 1
    var revealProgress: Double = 1
    var edgeHighlight: Double = 1

    init(
        family: AchievementFamily,
        stageKey: String,
        size: CGFloat = 72,
        rotationY: Double = 0,
        crackIntensity: Double = 1,
        revealProgress: Double = 1,
        edgeHighlight: Double = 1
    ) {
        self.family = family
        self.stageKey = stageKey
        self.size = size
        self.rotationY = rotationY
        self.crackIntensity = crackIntensity
        self.revealProgress = revealProgress
        self.edgeHighlight = edgeHighlight
    }

    init(
        _ presentation: AchievementPresentation,
        size: CGFloat = 72,
        rotationY: Double = 0,
        crackIntensity: Double = 1,
        revealProgress: Double = 1,
        edgeHighlight: Double = 1
    ) {
        self.init(
            family: presentation.family,
            stageKey: presentation.stageKey,
            size: size,
            rotationY: rotationY,
            crackIntensity: crackIntensity,
            revealProgress: revealProgress,
            edgeHighlight: edgeHighlight
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(crackColor.opacity(0.075 * clampedCrack))
                .frame(width: size * 1.22, height: size * 1.22)
                .blur(radius: size * 0.15)

            medalBody
                .rotation3DEffect(
                    .degrees(rotationY),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.56
                )
                .shadow(
                    color: Color(hex: 0x071B19).opacity(0.25),
                    radius: size * 0.105,
                    x: CGFloat(sin(rotationY * .pi / 180)) * size * 0.035,
                    y: size * 0.075
                )
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var medalBody: some View {
        if let artworkAssetName {
            ZStack {
                Image(artworkAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 1.4, height: size * 1.4)
                    .opacity(0.34 + 0.66 * clampedReveal)
                    .modifier(MedalFaceVisibility(angle: rotationY, isFront: true))

                backFace
                    .frame(width: size * 1.26, height: size * 1.07)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .modifier(MedalFaceVisibility(angle: rotationY, isFront: false))
            }
        } else {
            ZStack {
                ForEach(0..<5, id: \.self) { layer in
                    AchievementSealShape()
                        .fill(edgeStoneColor)
                        .offset(
                            x: CGFloat(layer - 2) * size * 0.006,
                            y: CGFloat(layer) * size * 0.009
                        )
                }

                frontFace
                    .modifier(MedalFaceVisibility(angle: rotationY, isFront: true))

                backFace
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .modifier(MedalFaceVisibility(angle: rotationY, isFront: false))
            }
        }
    }

    /// Only milestones with supplied artwork replace the deterministic
    /// SwiftUI medal. Unmatched wealth stages keep the existing renderer.
    private var artworkAssetName: String? {
        guard family == .wealthMilestone else { return nil }

        switch stageKey {
        case "wealth-0": return "AchievementWealth100K"
        case "wealth-1": return "AchievementWealth200K"
        case "wealth-2": return "AchievementWealth500K"
        case "wealth-3": return "AchievementWealth1M"
        case "wealth-4": return "AchievementWealth2M"
        case "wealth-5": return "AchievementWealth5M"
        case "wealth-6": return "AchievementWealth10M"
        default: return nil
        }
    }

    private var frontFace: some View {
        ZStack {
            AchievementSealShape()
                .fill(stoneGradient)

            StoneTexture(seed: materialIndex)
                .opacity(0.26)
                .mask(AchievementSealShape())

            AchievementSealShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38 * clampedEdge),
                            Color.white.opacity(0.08),
                            Color(hex: 0x071B19).opacity(0.50)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.1, size * 0.022)
                )

            AchievementSealShape()
                .stroke(crackColor.opacity(0.24 * clampedEdge), lineWidth: max(0.8, size * 0.010))
                .padding(size * 0.105)

            AchievementSculpture(family: family)
                .frame(width: size * 0.52, height: size * 0.52)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0xD7E0DD), Color(hex: 0x83938E)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.34), radius: 1.4, y: 1.2)
                .opacity(sculptureReveal)

            CairnCrackShape()
                .trim(from: 0, to: clampedCrack)
                .stroke(
                    crackColor.opacity(0.28 + 0.68 * clampedCrack),
                    style: StrokeStyle(
                        lineWidth: max(1.1, size * 0.021),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: crackColor.opacity(0.56 * clampedCrack), radius: size * 0.038)
                .frame(width: size * 0.54, height: size * 0.58)

            Ellipse()
                .fill(Color.white.opacity(0.14 * clampedEdge))
                .frame(width: size * 0.44, height: size * 0.11)
                .rotationEffect(.degrees(-22))
                .offset(x: -size * 0.13, y: -size * 0.27)
                .blur(radius: size * 0.025)
                .mask(AchievementSealShape())

            stageNotches
        }
        .opacity(0.34 + 0.66 * clampedReveal)
    }

    private var backFace: some View {
        ZStack {
            AchievementSealShape()
                .fill(stoneGradient)

            StoneTexture(seed: materialIndex + 9)
                .opacity(0.30)
                .mask(AchievementSealShape())

            AchievementSealShape()
                .stroke(Color.white.opacity(0.24 * clampedEdge), lineWidth: max(1, size * 0.016))

            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(
                        ring == 1 ? crackColor.opacity(0.34) : Color.white.opacity(0.15),
                        lineWidth: max(0.8, size * 0.009)
                    )
                    .padding(size * (0.17 + CGFloat(ring) * 0.075))
            }

            VStack(spacing: size * 0.035) {
                Text("CAIRN")
                    .font(.system(size: size * 0.13, weight: .black, design: .rounded))
                    .tracking(size * 0.022)
                Text(verbatim: stageMark)
                    .font(.system(size: size * 0.09, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(Color(hex: 0xC7D2CE).opacity(0.74))
            .shadow(color: Color.black.opacity(0.42), radius: 1, y: 1)
        }
        .opacity(0.34 + 0.66 * clampedReveal)
    }

    private var stageNotches: some View {
        ForEach(0..<min(materialIndex + 1, 6), id: \.self) { notch in
            Circle()
                .fill(crackColor.opacity(0.62))
                .frame(width: max(2.4, size * 0.032), height: max(2.4, size * 0.032))
                .offset(y: -size * 0.415)
                .rotationEffect(.degrees(Double(notch) * 12 - Double(min(materialIndex, 5)) * 6))
        }
        .opacity(clampedEdge)
    }

    private var clampedCrack: Double { min(1, max(0, crackIntensity)) }
    private var clampedReveal: Double { min(1, max(0, revealProgress)) }
    private var clampedEdge: Double { min(1, max(0, edgeHighlight)) }

    /// One reveal value produces a deliberate order: carving first, edge last.
    private var sculptureReveal: Double {
        min(1, max(0, (clampedReveal - 0.12) / 0.52))
    }

    private var stageMark: String {
        stageKey.split(separator: "-").last.map(String.init) ?? "•"
    }

    private var materialIndex: Int {
        switch family {
        case .prologue:
            return 0
        case .wealthMilestone:
            return min(AchievementService.wealthStageIndex(from: stageKey) ?? 0, 6)
        case .monthlyAscent:
            return min(Int(stageKey.split(separator: "-").last ?? "0") ?? 0, 6)
        case .timeMark:
            let threshold = Int(stageKey.split(separator: "-").last ?? "3") ?? 3
            return min(AchievementService.timeMarkThresholds.firstIndex(of: threshold) ?? 0, 5)
        }
    }

    private var stoneGradient: LinearGradient {
        let colors: [Color]
        switch materialIndex {
        case 0:
            colors = [Color(hex: 0x2D3B38), Color(hex: 0x152522), Color(hex: 0x41514D)]
        case 1:
            colors = [Color(hex: 0x5B4B3B), Color(hex: 0x2B2722), Color(hex: 0x7A6249)]
        case 2:
            colors = [Color(hex: 0x315752), Color(hex: 0x17312E), Color(hex: 0x47736B)]
        case 3:
            colors = [Color(hex: 0x243D3A), Color(hex: 0x102321), Color(hex: 0x35605A)]
        case 4:
            colors = [Color(hex: 0x626C69), Color(hex: 0x303A38), Color(hex: 0x78827F)]
        default:
            colors = [Color(hex: 0x264E49), Color(hex: 0x102A27), Color(hex: 0x3C6861)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var crackColor: Color {
        materialIndex == 1 ? Color(hex: 0x76D2C6) : Color(hex: 0x53E1D0)
    }

    private var edgeStoneColor: Color {
        materialIndex == 1 ? Color(hex: 0x201C18) : Color(hex: 0x0B1B19)
    }
}

private struct MedalFaceVisibility: @MainActor AnimatableModifier {
    var angle: Double
    let isFront: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let normalized = angle.truncatingRemainder(dividingBy: 360) * .pi / 180
        let frontFacing = cos(normalized) >= 0
        content.opacity(frontFacing == isFront ? 1 : 0)
    }
}

private struct StoneTexture: View {
    let seed: Int

    var body: some View {
        Canvas { context, size in
            for index in 0..<34 {
                let mixedX = abs((index + 3) * 73 + seed * 41) % 101
                let mixedY = abs((index + 7) * 47 + seed * 67) % 103
                let point = CGPoint(
                    x: size.width * CGFloat(mixedX) / 101,
                    y: size.height * CGFloat(mixedY) / 103
                )
                let radius = index.isMultiple(of: 5) ? 1.25 : 0.65
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x, y: point.y, width: radius, height: radius)),
                    with: .color(index.isMultiple(of: 3) ? Color.white.opacity(0.22) : Color.black.opacity(0.28))
                )
            }
        }
        .blendMode(.softLight)
    }
}

private struct AchievementSealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: 0.31, y: 0.03), CGPoint(x: 0.70, y: 0.06),
            CGPoint(x: 0.94, y: 0.27), CGPoint(x: 0.96, y: 0.68),
            CGPoint(x: 0.73, y: 0.94), CGPoint(x: 0.28, y: 0.97),
            CGPoint(x: 0.05, y: 0.74), CGPoint(x: 0.03, y: 0.32)
        ]
        var path = Path()
        path.move(to: CGPoint(x: points[0].x * rect.width, y: points[0].y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * rect.width, y: point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}

private struct CairnCrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.09))
        path.addLine(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.width * 0.57, y: rect.height * 0.47))
        path.addLine(to: CGPoint(x: rect.width * 0.46, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 0.53, y: rect.height * 0.91))

        path.move(to: CGPoint(x: rect.width * 0.46, y: rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.width * 0.27, y: rect.height * 0.45))
        path.addLine(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.59))

        path.move(to: CGPoint(x: rect.width * 0.53, y: rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.61))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.73))
        return path
    }
}

private struct AchievementSculpture: View {
    let family: AchievementFamily

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let primary = GraphicsContext.Shading.color(Color.white.opacity(0.90))
            let secondary = GraphicsContext.Shading.color(Color.white.opacity(0.40))

            switch family {
            case .prologue:
                context.fill(stone(in: bounds.insetBy(dx: size.width * 0.10, dy: size.height * 0.24)), with: primary)
                var seam = Path()
                seam.move(to: CGPoint(x: size.width * 0.48, y: size.height * 0.28))
                seam.addLine(to: CGPoint(x: size.width * 0.43, y: size.height * 0.48))
                seam.addLine(to: CGPoint(x: size.width * 0.53, y: size.height * 0.70))
                context.stroke(seam, with: secondary, lineWidth: max(1.5, size.width * 0.055))

            case .wealthMilestone:
                context.fill(stone(in: CGRect(x: size.width * 0.08, y: size.height * 0.60, width: size.width * 0.84, height: size.height * 0.25)), with: primary)
                context.fill(stone(in: CGRect(x: size.width * 0.20, y: size.height * 0.36, width: size.width * 0.62, height: size.height * 0.23)), with: primary)
                context.fill(stone(in: CGRect(x: size.width * 0.34, y: size.height * 0.14, width: size.width * 0.36, height: size.height * 0.21)), with: primary)

            case .monthlyAscent:
                var lower = Path()
                lower.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.72))
                lower.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.62))
                lower.addLine(to: CGPoint(x: size.width * 0.91, y: size.height * 0.32))
                lower.addLine(to: CGPoint(x: size.width * 0.91, y: size.height * 0.55))
                lower.addLine(to: CGPoint(x: size.width * 0.57, y: size.height * 0.84))
                lower.addLine(to: CGPoint(x: size.width * 0.08, y: size.height * 0.88))
                lower.closeSubpath()
                context.fill(lower, with: primary)
                var seam = Path()
                seam.move(to: CGPoint(x: size.width * 0.13, y: size.height * 0.58))
                seam.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.49))
                seam.addLine(to: CGPoint(x: size.width * 0.83, y: size.height * 0.20))
                context.stroke(seam, with: secondary, lineWidth: max(2, size.width * 0.09))

            case .timeMark:
                for inset in [0.08, 0.22, 0.36] {
                    let ring = bounds.insetBy(dx: size.width * inset, dy: size.height * inset)
                    context.stroke(Path(ellipseIn: ring), with: inset == 0.36 ? primary : secondary, lineWidth: max(1.5, size.width * 0.055))
                }
                context.fill(stone(in: CGRect(x: size.width * 0.36, y: size.height * 0.39, width: size.width * 0.30, height: size.height * 0.25)), with: primary)
            }
        }
    }

    private func stone(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.midY),
            control: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
