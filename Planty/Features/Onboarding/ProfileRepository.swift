import Foundation
import Supabase

struct OnboardingAnswers: Equatable, Sendable {
    enum PlantCount: String, CaseIterable, Sendable { case none, oneToThree = "1-3", fourToTen = "4-10", elevenPlus = "11+" }
    enum Experience: String, CaseIterable, Sendable { case beginner, experienced }
    enum Spot: String, CaseIterable, Sendable { case livingRoom = "living_room", bedroom, kitchen, bathroom, office, balcony }
    enum Frequency: String, CaseIterable, Sendable { case daily, fewTimesWeek = "few_times_week", weekly, rarely }

    var plantCount: PlantCount?
    var experience: Experience?
    var spots: Set<Spot> = []
    var frequency: Frequency?
    var wantsDailyReminders: Bool?
}

struct Profile: Equatable, Sendable {
    let id: UUID
    var preferredLanguage: String
    var onboardingCompleted: Bool
}

protocol ProfileRepository: Sendable {
    func profile(for userID: UUID) async throws -> Profile
    func saveOnboarding(_ answers: OnboardingAnswers, for userID: UUID) async throws
}

struct SupabaseProfileRepository: ProfileRepository {
    let client: SupabaseClient

    private struct Row: Decodable {
        let id: UUID
        let preferred_language: String
        let onboarding_completed_at: String?
    }

    private struct OnboardingUpdate: Encodable {
        let plant_count_range: String?
        let experience_level: String?
        let plant_locations: [String]
        let care_frequency: String?
        let wants_daily_reminders: Bool?
        let preferred_language: String
        let onboarding_completed_at: String
    }

    func profile(for userID: UUID) async throws -> Profile {
        let row: Row = try await client.from("profiles")
            .select("id, preferred_language, onboarding_completed_at")
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        return Profile(id: row.id, preferredLanguage: row.preferred_language, onboardingCompleted: row.onboarding_completed_at != nil)
    }

    func saveOnboarding(_ answers: OnboardingAnswers, for userID: UUID) async throws {
        let update = OnboardingUpdate(
            plant_count_range: answers.plantCount?.rawValue,
            experience_level: answers.experience?.rawValue,
            plant_locations: answers.spots.map(\.rawValue).sorted(),
            care_frequency: answers.frequency?.rawValue,
            wants_daily_reminders: answers.wantsDailyReminders,
            preferred_language: Self.supportedLanguage(),
            onboarding_completed_at: ISO8601DateFormatter().string(from: Date())
        )
        try await client.from("profiles")
            .update(update)
            .eq("id", value: userID)
            .execute()
    }

    static func supportedLanguage(_ preferred: [String] = Locale.preferredLanguages) -> String {
        for code in preferred {
            let base = String(code.prefix(2))
            if ["en", "de", "ru"].contains(base) { return base }
        }
        return "en"
    }
}
