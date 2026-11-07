import SwiftUI
import UserNotifications

/// Five short questions, all skippable, then a notification explainer before the system prompt.
struct OnboardingView: View {
    @Environment(SessionStore.self) private var session
    @State private var answers = OnboardingAnswers()
    @State private var step = 0
    @State private var isSaving = false

    private let questionCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: PlantySpacing.l) {
            HStack {
                ProgressView(value: Double(min(step, questionCount)), total: Double(questionCount))
                    .tint(Color.plantySage)
                if step < questionCount {
                    Button("Skip") { advance() }
                        .font(.plantyHeadline)
                }
            }

            Group {
                switch step {
                case 0:
                    question("How many plants do you have?") {
                        choices(OnboardingAnswers.PlantCount.allCases, selected: Set([answers.plantCount].compactMap { $0 })) {
                            answers.plantCount = $0; advance()
                        }
                    }
                case 1:
                    question("How experienced are you with plants?") {
                        choices(OnboardingAnswers.Experience.allCases, selected: Set([answers.experience].compactMap { $0 })) {
                            answers.experience = $0; advance()
                        }
                    }
                case 2:
                    question("Where do your plants live?", hint: "Pick all that apply.") {
                        choices(OnboardingAnswers.Spot.allCases, selected: answers.spots) { spot in
                            if answers.spots.contains(spot) { answers.spots.remove(spot) } else { answers.spots.insert(spot) }
                        }
                        Button("Continue") { advance() }
                            .buttonStyle(.plantyPrimary)
                            .padding(.top, PlantySpacing.s)
                    }
                case 3:
                    question("How often do you usually care for them?") {
                        choices(OnboardingAnswers.Frequency.allCases, selected: Set([answers.frequency].compactMap { $0 })) {
                            answers.frequency = $0; advance()
                        }
                    }
                case 4:
                    question("Would you like a daily reminder?", hint: "One calm nudge a day, only when a plant may need something.") {
                        Button("Yes, remind me") { answers.wantsDailyReminders = true; advance() }
                            .buttonStyle(.plantyPrimary)
                        Button("No, thanks") { answers.wantsDailyReminders = false; advance() }
                            .buttonStyle(.plantySecondary)
                    }
                default:
                    notificationExplainer
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            if let error = session.lastError {
                Text(error).font(.plantyCaption).foregroundStyle(Color.plantyCritical)
            }
        }
        .padding(PlantySpacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .plantyScreenBackground()
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var notificationExplainer: some View {
        VStack(alignment: .leading, spacing: PlantySpacing.m) {
            PlantAvatarView(mood: .thirsty, growthStage: .growing)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            Text("Never forget a thirsty plant")
                .font(.plantyLargeTitle)
                .foregroundStyle(Color.plantyTextPrimary)
            Text("Planty can remind you when a plant may need water, food or a check. You choose the time and quiet hours in Profile.")
                .font(.plantyBody)
                .foregroundStyle(Color.plantyTextSecondary)
            Spacer()
            Button {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    await finish()
                }
            } label: {
                if isSaving { ProgressView().tint(Color.plantyOnForest) } else { Text("Turn on reminders") }
            }
            .buttonStyle(.plantyPrimary)
            .disabled(isSaving)
            Button("Not now") { Task { await finish() } }
                .buttonStyle(.plantySecondary)
                .disabled(isSaving)
        }
    }

    private func advance() {
        if step == questionCount - 1, answers.wantsDailyReminders == false {
            Task { await finish() }
            return
        }
        step += 1
    }

    private func finish() async {
        isSaving = true
        await session.completeOnboarding(answers)
        isSaving = false
    }

    private func question<Content: View>(_ title: LocalizedStringKey, hint: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PlantySpacing.m) {
            Text(title)
                .font(.plantyLargeTitle)
                .foregroundStyle(Color.plantyTextPrimary)
            if let hint {
                Text(hint).font(.plantyBody).foregroundStyle(Color.plantyTextSecondary)
            }
            content()
        }
    }

    private func choices<Option: OnboardingOption>(_ options: [Option], selected: Set<Option>, onTap: @escaping (Option) -> Void) -> some View {
        VStack(spacing: PlantySpacing.s) {
            ForEach(options, id: \.self) { option in
                Button { onTap(option) } label: {
                    HStack {
                        Text(option.title).font(.plantyHeadline)
                        Spacer()
                        if selected.contains(option) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.plantyForest)
                        }
                    }
                    .padding(.horizontal, PlantySpacing.m)
                    .frame(minHeight: 52)
                    .foregroundStyle(Color.plantyTextPrimary)
                    .background(
                        selected.contains(option) ? Color.plantyMint : Color.plantySurface,
                        in: RoundedRectangle(cornerRadius: PlantyRadius.button, style: .continuous)
                    )
                }
                .accessibilityAddTraits(selected.contains(option) ? .isSelected : [])
            }
        }
    }
}

protocol OnboardingOption: Hashable {
    var title: LocalizedStringKey { get }
}

extension OnboardingAnswers.PlantCount: OnboardingOption {
    var title: LocalizedStringKey {
        switch self {
        case .none: return "None yet"
        case .oneToThree: return "1 to 3"
        case .fourToTen: return "4 to 10"
        case .elevenPlus: return "More than 10"
        }
    }
}

extension OnboardingAnswers.Experience: OnboardingOption {
    var title: LocalizedStringKey {
        switch self {
        case .beginner: return "I'm just starting"
        case .experienced: return "I know my way around"
        }
    }
}

extension OnboardingAnswers.Spot: OnboardingOption {
    var title: LocalizedStringKey {
        switch self {
        case .livingRoom: return "Living room"
        case .bedroom: return "Bedroom"
        case .kitchen: return "Kitchen"
        case .bathroom: return "Bathroom"
        case .office: return "Office"
        case .balcony: return "Balcony or garden"
        }
    }
}

extension OnboardingAnswers.Frequency: OnboardingOption {
    var title: LocalizedStringKey {
        switch self {
        case .daily: return "Every day"
        case .fewTimesWeek: return "A few times a week"
        case .weekly: return "About once a week"
        case .rarely: return "When I remember"
        }
    }
}
