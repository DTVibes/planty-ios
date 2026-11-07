import PlantyKit
import SwiftUI

struct GardenView: View {
    @Environment(SessionStore.self) private var session

    // Garden progress comes from the server-validated `user_progress` table from Step 4 on.
    private let totalXP = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlantySpacing.m) {
                Text(greeting)
                    .font(.plantyBody)
                    .foregroundStyle(Color.plantyTextSecondary)

                levelCard

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.plantyMint)
                    PlantAvatarView(mood: .neutral, growthStage: .small)
                        .frame(height: 140)
                        .padding(.bottom, PlantySpacing.l)
                }
                .frame(height: 240)
                .accessibilityHidden(true)

                PlantyEmptyState(
                    title: "Your garden is waiting",
                    message: "Soon you'll add your plants here, and each one becomes a little character that shows how it's doing."
                ) { EmptyView() }
            }
            .padding(PlantySpacing.m)
        }
        .plantyScreenBackground()
        .navigationTitle("My Garden")
    }

    private var greeting: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var levelCard: some View {
        let level = GardenLevel.level(forTotalXP: totalXP)
        let start = GardenLevel.threshold(for: level)
        let next = GardenLevel.threshold(for: level + 1)
        return VStack(alignment: .leading, spacing: PlantySpacing.s) {
            HStack {
                Text("Garden level \(level)").font(.plantyHeadline)
                Spacer()
                Text("\(totalXP) XP").font(.plantyCaption).foregroundStyle(Color.plantyTextSecondary)
            }
            ProgressView(value: Double(totalXP - start), total: Double(max(1, next - start)))
                .tint(Color.plantySage)
            Text("\(next - totalXP) XP to level \(level + 1)")
                .font(.plantyCaption)
                .foregroundStyle(Color.plantyTextSecondary)
        }
        .plantyCard()
    }
}
