import PlantyKit
import SwiftUI

struct PlantyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.plantyHeadline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color.plantyOnForest)
            .background(Color.plantyForest, in: RoundedRectangle(cornerRadius: PlantyRadius.button, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PlantySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.plantyHeadline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color.plantyTextPrimary)
            .background(Color.plantySurface, in: RoundedRectangle(cornerRadius: PlantyRadius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PlantyRadius.button, style: .continuous).stroke(Color.plantyBeige))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PlantyPrimaryButtonStyle {
    static var plantyPrimary: PlantyPrimaryButtonStyle { PlantyPrimaryButtonStyle() }
}

extension ButtonStyle where Self == PlantySecondaryButtonStyle {
    static var plantySecondary: PlantySecondaryButtonStyle { PlantySecondaryButtonStyle() }
}

struct PlantyCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PlantySpacing.m)
            .background(Color.plantySurface, in: RoundedRectangle(cornerRadius: PlantyRadius.card, style: .continuous))
            .shadow(color: Color.plantyForest.opacity(0.08), radius: 12, y: 6)
    }
}

extension View {
    func plantyCard() -> some View { modifier(PlantyCardModifier()) }

    func plantyScreenBackground() -> some View {
        background(Color.plantyBackground.ignoresSafeArea())
    }
}

/// Mood pill. Colour is always paired with the mood's name, never colour alone.
struct MoodBadge: View {
    let mood: PlantMood

    var body: some View {
        Text(mood.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(mood.foreground)
            .background(mood.background, in: Capsule())
    }
}

extension PlantMood {
    var title: LocalizedStringKey {
        switch self {
        case .thriving: return "Thriving"
        case .happy: return "Happy"
        case .neutral: return "Neutral"
        case .thirsty: return "Thirsty"
        case .needsAttention: return "Needs attention"
        }
    }

    var foreground: Color {
        switch self {
        case .thriving: return Color(light: 0x2E6B40, dark: 0xA8D9B4)
        case .happy: return .plantyForest
        case .neutral: return .plantyTextSecondary
        case .thirsty: return Color(light: 0x1F5F7E, dark: 0xA9D8EE)
        case .needsAttention: return Color(light: 0x9A3F37, dark: 0xF1B5AF)
        }
    }

    var background: Color {
        switch self {
        case .thriving: return Color(light: 0xE2F1E6, dark: 0x24402F)
        case .happy: return .plantyMint
        case .neutral: return Color(light: 0xEFECE3, dark: 0x2A302B)
        case .thirsty: return Color(light: 0xE3F1F8, dark: 0x1C3542)
        case .needsAttention: return Color(light: 0xF8E4E1, dark: 0x45282A)
        }
    }
}

/// Five-step estimate gauge (for example estimated soil moisture). Always shown with
/// a caption that says it is an estimate.
struct EstimateGauge: View {
    let title: LocalizedStringKey
    /// 0...4
    let level: Int
    let caption: LocalizedStringKey
    var tint: Color = .plantyWater

    var body: some View {
        VStack(alignment: .leading, spacing: PlantySpacing.s) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("Estimate").font(.caption).foregroundStyle(Color.plantyTextSecondary)
            }
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { step in
                    Capsule()
                        .fill(step < level ? tint : tint.opacity(0.2))
                        .frame(height: 8)
                }
            }
            .accessibilityHidden(true)
            Text(caption).font(.caption).foregroundStyle(Color.plantyTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Empty state used before a section has content. It has no buttons unless the
/// action really works.
struct PlantyEmptyState<Accessory: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: PlantySpacing.m) {
            accessory
            Text(title)
                .font(.plantyTitle)
                .foregroundStyle(Color.plantyTextPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.plantyBody)
                .foregroundStyle(Color.plantyTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(PlantySpacing.l)
        .frame(maxWidth: .infinity)
    }
}
