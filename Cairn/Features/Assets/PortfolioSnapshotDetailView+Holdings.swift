import SwiftUI

extension PortfolioSnapshotDetailView {
    /// Captured holdings grouped by member: a two-column card grid on macOS
    /// and a single divided list elsewhere.
    struct HoldingsCard: View {
        @Environment(\.locale) private var locale
        @Environment(LocalizationService.self) private var localization

        let groups: [MemberGroup]
        let homeCurrency: String
        /// Live members keyed by name, for avatar display.
        let memberByName: [String: Member]
        @Binding var hoveredEntryID: UUID?
        @Binding var convertedEntryID: UUID?

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("portfolioSnapshot.detail.breakdown")
                #if os(macOS)
                memberCardsGrid
                #else
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.member) { index, group in
                        memberGroupCard(group)
                        if index < groups.count - 1 {
                            Divider()
                                .opacity(0.45)
                                .padding(.vertical, 12)
                        }
                    }
                }
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Metrics.cardCornerRadius, padding: Metrics.cardPadding)
        }

        #if os(macOS)
        private var memberCardsGrid: some View {
            let pairs: [[MemberGroup]] = stride(from: 0, to: groups.count, by: 2).map { start in
                Array(groups[start..<min(start + 2, groups.count)])
            }
            return VStack(spacing: 12) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(pair, id: \.member) { group in
                            memberGroupCard(group)
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                        if pair.count == 1 {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        #endif

        private func memberGroupCard(_ group: MemberGroup) -> some View {
            #if os(macOS)
            memberGroupSection(group)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Color.notionSurfaceAlt.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.line.opacity(0.65), lineWidth: 0.7)
                )
            #else
            memberGroupSection(group)
                .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }

        @ViewBuilder
        private func memberGroupSection(_ group: MemberGroup) -> some View {
            let displayName = group.member.isEmpty
                ? String(localized: "portfolioSnapshot.detail.member.unassigned", bundle: localization.bundle)
                : group.member
            let resolvedMember = group.member.isEmpty ? nil : memberByName[group.member]
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 8) {
                        MemberAvatarView(
                            name: displayName,
                            avatarData: resolvedMember?.avatarData,
                            seed: resolvedMember?.id ?? Self.unassignedMemberSeed,
                            size: Metrics.memberAvatarSize
                        )
                        Text(verbatim: displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ink)
                        Spacer(minLength: 8)
                        Text(
                            group.total,
                            format: .currency(code: homeCurrency)
                                .precision(.fractionLength(0))
                                .locale(locale)
                        )
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.ink2)
                    }
                    if let memberDelta = group.delta {
                        HStack {
                            Spacer(minLength: 0)
                            InlineDelta(amount: memberDelta, currency: homeCurrency)
                        }
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(group.entries.enumerated()), id: \.element.current.id) { index, row in
                        EntryRowView(
                            row: row,
                            homeCurrency: homeCurrency,
                            hoveredEntryID: $hoveredEntryID,
                            convertedEntryID: $convertedEntryID
                        )
                        if index < group.entries.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }

        private static let unassignedMemberSeed = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }
}
