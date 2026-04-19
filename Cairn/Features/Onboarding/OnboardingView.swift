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

    enum Step: Int {
        case welcome, homeCurrency, firstMember
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .homeCurrency: currencyStep
                case .firstMember: firstMemberStep
                }
            }
            .navigationTitle("onboarding.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .padding()
        }
        .interactiveDismissDisabled(true)
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("onboarding.welcome.title")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("onboarding.welcome.body")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Spacer()
            Button {
                step = .homeCurrency
            } label: {
                Text("onboarding.continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var currencyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("onboarding.homeCurrency.title")
                .font(.title2.bold())
            Text("onboarding.homeCurrency.body")
                .foregroundStyle(.secondary)
            Form {
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
            }
            Button {
                step = .firstMember
            } label: {
                Text("onboarding.continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var firstMemberStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("onboarding.firstMember.title")
                .font(.title2.bold())
            Text("onboarding.firstMember.body")
                .foregroundStyle(.secondary)
            Form {
                TextField("member.form.name", text: $memberName)
            }
            Button {
                finish()
            } label: {
                Text("onboarding.finish")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
