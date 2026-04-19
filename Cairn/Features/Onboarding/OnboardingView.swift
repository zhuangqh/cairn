import SwiftUI
import SwiftData

/// First-run onboarding: pick home currency and create the first Member.
/// Dismissed by flipping `onboardingCompleted` to true.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @AppStorage(AppSettingsKeys.onboardingCompleted)
    private var onboardingCompleted: Bool = false

    @State private var memberName: String = ""
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, homeCurrency, firstMember
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                progressDots
                Group {
                    switch step {
                    case .welcome: welcome
                    case .homeCurrency: currencyStep
                    case .firstMember: firstMemberStep
                    }
                }
                .glassCard(cornerRadius: 24, padding: 28)
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 40)
        }
        .interactiveDismissDisabled(true)
        .frame(minWidth: 560, minHeight: 520)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: item == step ? 22 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.7), .accentColor.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            Text("onboarding.welcome.title")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("onboarding.welcome.body")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            primaryButton(label: "onboarding.continue") {
                step = .homeCurrency
            }
        }
    }

    private var currencyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("onboarding.homeCurrency.title", body: "onboarding.homeCurrency.body")
            Picker(selection: $homeCurrency) {
                Section("currency.picker.pinned") {
                    ForEach(CurrencyCatalog.pinned, id: \.self) { code in
                        currencyLabel(code).tag(code)
                    }
                }
                Section("currency.picker.other") {
                    ForEach(CurrencyCatalog.rest, id: \.self) { code in
                        currencyLabel(code).tag(code)
                    }
                }
            } label: {
                Text("settings.homeCurrency.title")
            }
            .pickerStyle(.menu)
            .padding(.vertical, 4)

            primaryButton(label: "onboarding.continue") {
                step = .firstMember
            }
        }
    }

    private var firstMemberStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("onboarding.firstMember.title", body: "onboarding.firstMember.body")
            TextField("member.form.name", text: $memberName)
                .textFieldStyle(.roundedBorder)

            VStack(spacing: 10) {
                primaryButton(label: "onboarding.finish") {
                    finish()
                }
                .disabled(memberName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    finish()
                } label: {
                    Text("onboarding.skip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Helpers

    private func stepTitle(_ titleKey: LocalizedStringKey, body bodyKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleKey)
                .font(.title2.bold())
            Text(bodyKey)
                .foregroundStyle(.secondary)
        }
    }

    private func primaryButton(label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private func currencyLabel(_ code: String) -> some View {
        HStack {
            Text(verbatim: code).font(.body.monospaced())
            Text(verbatim: CurrencyCatalog.displayName(code))
                .foregroundStyle(.secondary)
        }
    }

    private func finish() {
        let trimmed = memberName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let member = Member(name: trimmed)
            context.insert(member)
            try? context.save()
        }
        onboardingCompleted = true
    }
}

#Preview {
    OnboardingView()
        .modelContainer(PersistenceController.previewContainer())
}
