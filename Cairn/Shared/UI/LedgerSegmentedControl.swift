import SwiftUI

/// Page-level segmented control (design.md §5.7), e.g. Financial / Physical.
/// A 6% ink track with a raised ivory thumb under the selected option.
/// Animates with a critically damped spring, or a fade under Reduce Motion.
struct LedgerSegmentedControl<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> Text

    @Namespace private var thumbNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.ink.opacity(0.06))
        )
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 1),
            value: selection
        )
    }

    private func segment(for option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            title(option)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.ink : Color.ink2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(light: Color(hex: 0xFDFCF9), dark: Color(hex: 0x2A302C)))
                            .shadow(color: .black.opacity(0.07), radius: 1.5, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumbNamespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("LedgerSegmentedControl") {
    struct Host: View {
        @State private var selection = 0
        var body: some View {
            LedgerSegmentedControl(selection: $selection, options: [0, 1]) { option in
                Text(verbatim: option == 0 ? "Financial" : "Physical")
            }
            .padding()
            .background(Color.pageBackground)
        }
    }
    return Host()
}
