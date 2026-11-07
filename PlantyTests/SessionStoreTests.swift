import XCTest
@testable import Planty

@MainActor
final class SessionStoreTests: XCTestCase {
    private let alice = AppUser(id: UUID(), email: "alice@example.com", isGuest: false)

    func testSignedOutWithoutSession() async {
        let store = SessionStore(auth: FakeAuth(), profiles: FakeProfiles())
        await store.start()
        XCTAssertEqual(store.state, .signedOut)
    }

    func testNewUserGoesToOnboarding() async {
        let auth = FakeAuth()
        let profiles = FakeProfiles()
        let store = SessionStore(auth: auth, profiles: profiles)
        await store.start()
        await store.signIn(email: "alice@example.com", password: "secret123")
        XCTAssertEqual(store.state, .onboarding(auth.user))
    }

    func testReturningUserGoesStraightToGarden() async {
        let auth = FakeAuth(current: alice)
        let profiles = FakeProfiles(completed: [alice.id])
        let store = SessionStore(auth: auth, profiles: profiles)
        await store.start()
        XCTAssertEqual(store.state, .ready(alice))
    }

    func testCompletingOnboardingSavesAnswers() async {
        let auth = FakeAuth(current: alice)
        let profiles = FakeProfiles()
        let store = SessionStore(auth: auth, profiles: profiles)
        await store.start()
        var answers = OnboardingAnswers()
        answers.experience = .beginner
        await store.completeOnboarding(answers)
        XCTAssertEqual(store.state, .ready(alice))
        XCTAssertEqual(profiles.saved[alice.id]?.experience, .beginner)
    }

    func testFailedSignInShowsErrorAndStaysSignedOut() async {
        let auth = FakeAuth(failure: .invalidCredentials)
        let store = SessionStore(auth: auth, profiles: FakeProfiles())
        await store.start()
        await store.signIn(email: "alice@example.com", password: "wrong")
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(store.lastError, AuthError.invalidCredentials.localizedDescription)
    }

    func testGuestSignIn() async {
        let auth = FakeAuth()
        let store = SessionStore(auth: auth, profiles: FakeProfiles())
        await store.start()
        await store.continueAsGuest()
        XCTAssertEqual(store.user?.isGuest, true)
    }

    func testEmailConfirmationKeepsUserSignedOut() async {
        let auth = FakeAuth(requiresConfirmation: true)
        let store = SessionStore(auth: auth, profiles: FakeProfiles())
        await store.start()
        let needsConfirmation = await store.signUp(email: "new@example.com", password: "longenough")
        XCTAssertTrue(needsConfirmation)
        XCTAssertEqual(store.state, .signedOut)
    }

    func testSignOut() async {
        let store = SessionStore(auth: FakeAuth(current: alice), profiles: FakeProfiles(completed: [alice.id]))
        await store.start()
        await store.signOut()
        XCTAssertEqual(store.state, .signedOut)
    }

    func testLanguageFallsBackToEnglish() {
        XCTAssertEqual(SupabaseProfileRepository.supportedLanguage(["ru-RU", "en"]), "ru")
        XCTAssertEqual(SupabaseProfileRepository.supportedLanguage(["fr-FR", "de-AT"]), "de")
        XCTAssertEqual(SupabaseProfileRepository.supportedLanguage(["ja-JP"]), "en")
    }
}

// MARK: - Fakes

private final class FakeAuth: AuthService, @unchecked Sendable {
    let user = AppUser(id: UUID(), email: "alice@example.com", isGuest: false)
    private var current: AppUser?
    private let failure: AuthError?
    private let requiresConfirmation: Bool

    init(current: AppUser? = nil, failure: AuthError? = nil, requiresConfirmation: Bool = false) {
        self.current = current
        self.failure = failure
        self.requiresConfirmation = requiresConfirmation
    }

    func currentUser() async -> AppUser? { current }
    func userChanges() -> AsyncStream<AppUser?> { AsyncStream { _ in } }

    func signInWithApple(idToken: String, nonce: String) async throws -> AppUser { try signedIn(user) }
    func signIn(email: String, password: String) async throws -> AppUser { try signedIn(user) }
    func continueAsGuest() async throws -> AppUser { try signedIn(AppUser(id: UUID(), email: nil, isGuest: true)) }

    func signUp(email: String, password: String) async throws -> SignUpResult {
        if requiresConfirmation { return .confirmationSent }
        return .signedIn(try signedIn(user))
    }

    func signOut() async throws { current = nil }

    private func signedIn(_ user: AppUser) throws -> AppUser {
        if let failure { throw failure }
        current = user
        return user
    }
}

private final class FakeProfiles: ProfileRepository, @unchecked Sendable {
    private var completed: Set<UUID>
    private(set) var saved: [UUID: OnboardingAnswers] = [:]

    init(completed: Set<UUID> = []) { self.completed = completed }

    func profile(for userID: UUID) async throws -> Profile {
        Profile(id: userID, preferredLanguage: "en", onboardingCompleted: completed.contains(userID))
    }

    func saveOnboarding(_ answers: OnboardingAnswers, for userID: UUID) async throws {
        saved[userID] = answers
        completed.insert(userID)
    }
}
