import Foundation
import Observation

/// Owns who is signed in and which part of the app to show.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case loading
        case signedOut
        case onboarding(AppUser)
        case ready(AppUser)
        /// The backend is not configured or unreachable at launch.
        case failed(String)
    }

    private(set) var state: State = .loading
    var lastError: String?

    private let auth: AuthService
    private let profiles: ProfileRepository
    private var listener: Task<Void, Never>?

    init(auth: AuthService, profiles: ProfileRepository) {
        self.auth = auth
        self.profiles = profiles
    }

    var user: AppUser? {
        switch state {
        case .onboarding(let user), .ready(let user): return user
        default: return nil
        }
    }

    func start() async {
        await route(await auth.currentUser())
        listener?.cancel()
        listener = Task { [weak self, auth] in
            for await user in auth.userChanges() {
                guard let self else { return }
                if user?.id != self.user?.id { await self.route(user) }
            }
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        await perform { try await self.auth.signInWithApple(idToken: idToken, nonce: nonce) }
    }

    func signIn(email: String, password: String) async {
        await perform { try await self.auth.signIn(email: email, password: password) }
    }

    /// Returns true when the user has to confirm their email before signing in.
    func signUp(email: String, password: String) async -> Bool {
        lastError = nil
        do {
            switch try await auth.signUp(email: email, password: password) {
            case .signedIn(let user):
                await route(user)
                return false
            case .confirmationSent:
                return true
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func continueAsGuest() async {
        await perform { try await self.auth.continueAsGuest() }
    }

    func completeOnboarding(_ answers: OnboardingAnswers) async {
        guard let user else { return }
        lastError = nil
        do {
            try await profiles.saveOnboarding(answers, for: user.id)
            state = .ready(user)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await auth.signOut()
            state = .signedOut
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func perform(_ signIn: @escaping () async throws -> AppUser) async {
        lastError = nil
        do {
            await route(try await signIn())
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func route(_ user: AppUser?) async {
        guard let user else {
            state = .signedOut
            return
        }
        do {
            let profile = try await profiles.profile(for: user.id)
            state = profile.onboardingCompleted ? .ready(user) : .onboarding(user)
        } catch {
            // Offline at launch: let a returning user in; onboarding can resume later.
            state = .ready(user)
        }
    }
}
