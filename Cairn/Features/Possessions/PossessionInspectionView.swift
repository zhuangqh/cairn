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
    @State private var sourceRevealed = false
    @State private var editing: Possession?
    /// Opened in the editor once the overlay has fully dismissed.
    @State private var pendingEdit: Possession?

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(1 - 0.78 * progress)
                .allowsHitTesting(inspected == nil)
                .accessibilityHidden(inspected != nil)
                .environment(\.possessionInspector, PossessionInspector(inspectedID: sourceRevealed ? nil : inspected?.id, open: open))
        }
        .inspectionPresentation(
            isPresented: inspected != nil,
            onPresented: start,
            onDismissed: {
                editing = pendingEdit
                pendingEdit = nil
            }
        ) {
            // Emptied when the shelf item is revealed, so nothing is left in
            // the cover to animate while it dismisses.
            if let inspected, !sourceRevealed {
                PossessionInspectionView(
                    possession: inspected,
                    homeCurrency: homeCurrency,
                    homeEquivalent: homeEquivalent,
                    // Live frame, in case the shelf moves under the flight.
                    sourceFrame: sourceFrames[inspected.id.uuidString] ?? sourceFrame,
                    progress: progress,
                    canClose: task == nil && progress == 1,
                    onClose: { close(thenEdit: false) },
                    onEdit: { close(thenEdit: true) }
                )
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
        // The overlay animates itself once on screen (`start`).
        sourceRevealed = false
        withTransaction(\.disablesAnimations, true) {
            inspected = possession
        }
    }

    private func start() {
        guard inspected != nil, task == nil, progress == 0 else { return }
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
            if thenEdit { pendingEdit = possession }
            // Swap the landed copy for the real item, then dismiss the now
            // empty cover. Anything drawn while the cover dismisses animates
            // in from the screen's corner.
            sourceRevealed = true
            try? await Task.sleep(for: .milliseconds(34))
            withTransaction(\.disablesAnimations, true) {
                inspected = nil
            }
            task = nil
        }
    }
}

/// A possession displayed like an entry in the family asset register, with
/// its photograph above the purchase amount and ruled, scrollable details.
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LocalizationService.self) private var localization
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 32
    @State private var artworkFrame: CGRect = .zero

    var body: some View {
        ZStack {
            AppBackground()
                .modifier(AchievementInspectionReveal(progress: progress, start: 0, end: 0.44))

            VStack(spacing: 0) {
                HStack {
                    Text("possession.inspect.eyebrow", bundle: localization.bundle)
                        .font(.subheadline)
                        .foregroundStyle(Color.ink2)
                    Spacer(minLength: 12)
                    InspectionCloseButton(canClose: canClose, action: onClose)
                }
                .inspectionColumn()
                .modifier(copyReveal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        artwork
                            .padding(.top, 12)
                            .padding(.bottom, 24)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: possession.name)
                                .font(.system(size: titleSize, weight: .bold))
                                .tracking(-0.6)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            subtitle
                                .font(.subheadline)
                                .foregroundStyle(Color.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .modifier(copyReveal)

                        purchaseSummary
                            .modifier(copyReveal)
                        record
                            .modifier(copyReveal)

                        if let note = possession.note, !note.isEmpty {
                            LedgerSection(Text("possession.form.note", bundle: localization.bundle)) {
                                Text(verbatim: note)
                                    .font(.callout)
                                    .foregroundStyle(Color.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                    .padding(.vertical, 8)
                            }
                            .modifier(copyReveal)
                        }

                        Button(action: onEdit) {
                            Label {
                                Text("common.action.edit", bundle: localization.bundle)
                            } icon: {
                                Image(systemName: "pencil")
                            }
                            .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(Color.accent)
                        .foregroundStyle(colorScheme == .dark ? Color.pageBackground : .white)
                        .allowsHitTesting(canClose)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                        .modifier(copyReveal)
                    }
                    .inspectionColumn()
                }
                .scrollIndicators(.hidden)
            }

            InspectionFlightLayer(
                sourceFrame: sourceFrame,
                targetFrame: artworkFrame,
                progress: progress,
                isSettled: canClose
            ) { size in
                figure(size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A tap anywhere outside a control closes, so the small close glyph
        // is not the only way back. The host ignores taps mid-flight.
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityAddTraits(.isModal)
    }

    private var artwork: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            InspectionFlightSlot(isSettled: canClose, targetFrame: $artworkFrame) { size in
                figure(size)
            }
            .aspectRatio(PossessionArtwork.shelfSize, contentMode: .fit)
            .frame(maxWidth: 260)
            Spacer(minLength: 0)
        }
        .frame(height: 200)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.thumb)
                .modifier(AchievementInspectionReveal(progress: progress, start: 0.10, end: 0.58))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func figure(_ size: CGSize) -> some View {
        PossessionArtwork(possession: possession, size: size)
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .blendMode(colorScheme == .dark ? .normal : .multiply)
    }

    private var purchaseSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("possession.form.purchasePrice", bundle: localization.bundle)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink2)
                Spacer(minLength: 12)
                CurrencyChip(code: possession.purchaseCurrency)
            }
            LedgerHeroAmount(
                amount: possession.purchasePrice,
                code: possession.purchaseCurrency,
                locale: locale,
                fractionDigits: purchaseFractionDigits
            )
            if let homeEquivalent {
                Text(verbatim: "≈ " + money(homeEquivalent, homeCurrency))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink2)
            }
        }
        .padding(.vertical, 24)
    }

    private var record: some View {
        LedgerSection(Text("possession.inspect.record", bundle: localization.bundle)) {
            VStack(spacing: 0) {
                detailRow("possession.form.purchaseDate", value: purchaseDateText, secondary: heldText)
                if let current = possession.currentValue {
                    LedgerHairline()
                    detailRow("possession.form.currentValue", value: money(current, possession.purchaseCurrency))
                }
            }
        }
    }

    private func detailRow(_ label: LocalizedStringKey, value: String, secondary: String? = nil) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(label, bundle: localization.bundle).foregroundStyle(Color.ink2).fixedSize()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: value).foregroundStyle(Color.ink)
                    if let secondary {
                        Text(verbatim: secondary).font(.footnote).foregroundStyle(Color.ink2)
                    }
                }
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(label, bundle: localization.bundle).foregroundStyle(Color.ink2)
                Text(verbatim: value).foregroundStyle(Color.ink)
                if let secondary {
                    Text(verbatim: secondary).font(.footnote).foregroundStyle(Color.ink2)
                }
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var purchaseFractionDigits: Int {
        var whole = Decimal()
        var copy = possession.purchasePrice
        NSDecimalRound(&whole, &copy, 0, .plain)
        return whole == possession.purchasePrice
            ? 0
            : LedgerAmountFormat.minorUnits(for: possession.purchaseCurrency, locale: locale)
    }

    private var copyReveal: AchievementInspectionReveal {
        AchievementInspectionReveal(progress: progress, start: 0.62, end: 0.92)
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
