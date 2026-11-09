import SwiftUI
import SwiftData

/// Opens the showcase inspection for a possession. Provided by
/// `possessionInspectionHost()`; `nil` where no host is installed, in which
/// case the showcase falls back to opening the editor.
struct PossessionInspector {
    let inspectedID: UUID?
    let open: @MainActor (Possession) -> Void
}

private struct PossessionInspectorKey: EnvironmentKey {
    static var defaultValue: PossessionInspector? { nil }
}

extension EnvironmentValues {
    var possessionInspector: PossessionInspector? {
        get { self[PossessionInspectorKey.self] }
        set { self[PossessionInspectorKey.self] = newValue }
    }
}

extension View {
    /// Hosts the possession inspection overlay above this view (the whole
    /// Assets screen) along with the editor it hands off to. `isPresented`
    /// mirrors whether an item is open, for chrome outside the host such
    /// as toolbar items.
    func possessionInspectionHost(isPresented: Binding<Bool>) -> some View {
        modifier(PossessionInspectionHost(isPresented: isPresented))
    }
}

/// Owns the inspection state and the source-to-centre animation, mirroring
/// the achievement medal inspection so both share one motion language.
private struct PossessionInspectionHost: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @State private var inspected: Possession?
    @State private var homeEquivalent: Decimal?
    @State private var sourceFrame: CGRect = .zero
    @State private var sourceFrames: [String: CGRect] = [:]
    @State private var progress = 0.0
    @State private var task: Task<Void, Never>?
    @State private var editing: Possession?

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(1 - 0.78 * progress)
                .allowsHitTesting(inspected == nil)
                .environment(\.possessionInspector, PossessionInspector(inspectedID: inspected?.id, open: open))
            if let inspected {
                PossessionInspectionView(
                    possession: inspected,
                    homeCurrency: homeCurrency,
                    homeEquivalent: homeEquivalent,
                    sourceFrame: sourceFrame,
                    progress: progress,
                    canClose: task == nil && progress == 1,
                    onClose: { close(thenEdit: false) },
                    onEdit: { close(thenEdit: true) }
                )
                .zIndex(10)
            }
        }
        .onPreferenceChange(AchievementInspectionSourceFramesKey.self) { sourceFrames = $0 }
        .onChange(of: inspected == nil) { _, isClosed in isPresented = !isClosed }
        .sheet(item: $editing) { possession in
            PossessionFormView(possession: possession, isNew: false) { _ in
                editing = nil
            }
        }
        .onDisappear {
            // Leaving mid-flight must not strand the overlay unclosable.
            task?.cancel()
            task = nil
            inspected = nil
            progress = 0
        }
    }

    private func open(_ possession: Possession) {
        guard inspected == nil, task == nil,
              let frame = sourceFrames[possession.id.uuidString] else { return }
        sourceFrame = frame
        homeEquivalent = possession.purchaseCurrency == homeCurrency
            ? nil
            : FXService.RateCache.load(in: context).convert(
                amount: possession.purchasePrice,
                from: possession.purchaseCurrency,
                to: homeCurrency
            )
        progress = 0
        inspected = possession
        task = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let duration = reduceMotion ? 0.25 : 0.7
            withAnimation(reduceMotion
                ? .easeOut(duration: duration)
                : .timingCurve(0.18, 0.76, 0.22, 1, duration: duration)
            ) {
                progress = 1
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            task = nil
        }
    }

    private func close(thenEdit: Bool) {
        guard let possession = inspected, progress == 1, task == nil else { return }
        task = Task { @MainActor in
            let duration = reduceMotion ? 0.25 : 0.6
            withAnimation(reduceMotion
                ? .easeOut(duration: duration)
                : .timingCurve(0.30, 0, 0.24, 1, duration: duration)
            ) {
                progress = 0
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            inspected = nil
            task = nil
            if thenEdit { editing = possession }
        }
    }
}

/// Spotlit close-up of one showcase item: the artwork lifted from its shelf,
/// then a quiet card with what the household knows about it.
struct PossessionInspectionView: View {
    let possession: Possession
    let homeCurrency: String
    let homeEquivalent: Decimal?
    let sourceFrame: CGRect
    let progress: Double
    let canClose: Bool
    let onClose: () -> Void
    let onEdit: () -> Void

    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .overlay { Color(white: 0.04).opacity(0.86) }
                .modifier(AchievementInspectionReveal(progress: progress, start: 0, end: 0.44))
                .ignoresSafeArea()

            spotlight

            Button(action: onClose) {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .disabled(!canClose)
            .accessibilityLabel(Text("common.action.done"))
            .keyboardShortcut(.cancelAction)

            VStack(spacing: 24) {
                Spacer(minLength: 0)
                // Same aspect as the shelf box, so the flight lands exactly on
                // the shelf figure. It yields height first so the card's copy
                // wraps instead of truncating on short screens.
                GeometryReader { proxy in
                    PossessionArtwork(possession: possession, size: proxy.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        // Fades with the flight; the shelf has its own floor shadow.
                        .shadow(color: .black.opacity(0.45 * progress), radius: 18, y: 12)
                        .modifier(
                            AchievementInspectionMotion(
                                progress: reduceMotion ? 1 : progress,
                                sourceFrame: sourceFrame,
                                targetFrame: proxy.frame(in: .global)
                            )
                        )
                        .opacity(reduceMotion ? progress : 1)
                }
                .aspectRatio(PossessionArtwork.shelfSize, contentMode: .fit)
                .frame(maxWidth: 260, minHeight: 96, maxHeight: 200)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                infoCard
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(AchievementInspectionReveal(progress: progress, start: 0.62, end: 0.92, distance: 10))
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 680, maxHeight: 760)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
    }

    private var spotlight: some View {
        RadialGradient(
            colors: [Color(red: 1, green: 0.88, blue: 0.70).opacity(0.22), .clear],
            center: UnitPoint(x: 0.5, y: 0.22),
            startRadius: 0,
            endRadius: 380
        )
        .ignoresSafeArea()
        .modifier(AchievementInspectionReveal(progress: progress, start: 0.10, end: 0.58))
        .allowsHitTesting(false)
    }

    // MARK: - Card

    private var infoCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(verbatim: possession.name)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Text(verbatim: money(possession.purchasePrice, possession.purchaseCurrency))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.top, 4)
                if let homeEquivalent {
                    Text(verbatim: "≈ " + money(homeEquivalent, homeCurrency))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .accessibilityElement(children: .combine)

            Divider().overlay(Color.white.opacity(0.12))

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                detailRow("possession.form.purchaseDate", value: purchaseDateText, secondary: heldText)
                if let note = possession.note, !note.isEmpty {
                    // Capped so the actions stay reachable; the editor shows all of it.
                    detailRow("possession.form.note", value: note, valueLineLimit: 6)
                }
                if let current = possession.currentValue {
                    detailRow("possession.form.currentValue", value: money(current, possession.purchaseCurrency))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
                .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.065))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                }
        }
    }

    private func detailRow(
        _ label: LocalizedStringKey,
        value: String,
        secondary: String? = nil,
        valueLineLimit: Int? = nil
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: value)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(valueLineLimit)
                if let secondary {
                    Text(verbatim: secondary)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    /// Adding or replacing a photo happens in the editor, so Edit is the
    /// only action.
    private var actions: some View {
        Button(action: onEdit) {
            Label { Text("common.action.edit") } icon: { Image(systemName: "pencil") }
        }
        .buttonStyle(InspectionActionButtonStyle())
        .frame(maxWidth: 180)
        .allowsHitTesting(canClose)
    }

    // MARK: - Formatting

    private var subtitle: Text {
        let category = Text(LocalizedStringKey(possession.category.localizationKey))
        guard let member = possession.member else { return category }
        return category + Text(verbatim: " · \(member.name)")
    }

    /// Whole amounts drop the trailing ".00"; stored cents are always shown.
    private func money(_ amount: Decimal, _ code: String) -> String {
        let format = Decimal.FormatStyle.Currency(code: code).locale(locale)
        var whole = Decimal()
        var copy = amount
        NSDecimalRound(&whole, &copy, 0, .plain)
        return whole == amount
            ? amount.formatted(format.precision(.fractionLength(0)))
            : amount.formatted(format)
    }

    private var purchaseDateText: String {
        possession.purchaseDate.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
    }

    /// "Held for 3 years, 2 months" (days under a month).
    private var heldText: String? {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: possession.purchaseDate, to: .now)
        var components = DateComponents()
        if (parts.year ?? 0) > 0 || (parts.month ?? 0) > 0 {
            components.year = parts.year
            components.month = parts.month
        } else {
            components.day = max(parts.day ?? 0, 0)
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.year, .month, .day]
        formatter.zeroFormattingBehavior = .dropAll
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        guard let duration = formatter.string(from: components), !duration.isEmpty else { return nil }
        return String(localized: "possession.inspect.held", bundle: localization.bundle)
            .replacingOccurrences(of: "{duration}", with: duration)
    }
}

/// Translucent capsule action for the dark inspection backdrop.
private struct InspectionActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8) }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
