import Foundation
import Supabase

struct AppUser: Equatable, Sendable {
    let id: UUID
    let email: String?
    /// Guest accounts (Supabase anonymous sign-in). Their data syncs, but is lost if the
    /// app is deleted before the guest links Apple or email.
    let isGuest: Bool
}

enum AuthError: LocalizedError, Equatable {
    case invalidCredentials
    case emailNotConfirmed
    case weakPassword
    case appleTokenMissing
    case network
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return String(localized: "The email or password is not right.")
        case .emailNotConfirmed: return String(localized: "Please confirm your email first. We sent you a link.")
        case .weakPassword: return String(localized: "Use at least 8 characters for your password.")
        case .appleTokenMissing: return String(localized: "Sign in with Apple did not finish. Please try again.")
        case .network: return String(localized: "No connection. Check your internet and try again.")
        case .unknown(let message): return message
        }
    }
}

enum SignUpResult: Equatable {
    case signedIn(AppUser)
    /// Email confirmation is on: the user must open the link we sent.
    case confirmationSent
}

protocol AuthService: Sendable {
    func currentUser() async -> AppUser?
    func userChanges() -> AsyncStream<AppUser?>
    func signInWithApple(idToken: String, nonce: String) async throws -> AppUser
    func signUp(email: String, password: String) async throws -> SignUpResult
    func signIn(email: String, password: String) async throws -> AppUser
    func continueAsGuest() async throws -> AppUser
    func signOut() async throws
}

struct SupabaseAuthService: AuthService {
    let client: SupabaseClient

    func currentUser() async -> AppUser? {
        guard let session = try? await client.auth.session else { return nil }
        return AppUser(session.user)
    }

    func userChanges() -> AsyncStream<AppUser?> {
        let changes = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await change in changes {
                    continuation.yield(change.session.map { AppUser($0.user) })
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AppUser {
        try await mapErrors {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            return AppUser(session.user)
        }
    }

    func signUp(email: String, password: String) async throws -> SignUpResult {
        guard password.count >= 8 else { throw AuthError.weakPassword }
        return try await mapErrors {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                return .signedIn(AppUser(session.user))
            }
            return .confirmationSent
        }
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        try await mapErrors {
            let session = try await client.auth.signIn(email: email, password: password)
            return AppUser(session.user)
        }
    }

    func continueAsGuest() async throws -> AppUser {
        try await mapErrors {
            let session = try await client.auth.signInAnonymously()
            return AppUser(session.user)
        }
    }

    func signOut() async throws {
        try await mapErrors { try await client.auth.signOut() }
    }

    private func mapErrors<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as AuthError {
            throw error
        } catch is URLError {
            throw AuthError.network
        } catch {
            let message = String(describing: error).lowercased()
            if message.contains("invalid login credentials") || message.contains("invalid_credentials") {
                throw AuthError.invalidCredentials
            }
            if message.contains("email not confirmed") || message.contains("email_not_confirmed") {
                throw AuthError.emailNotConfirmed
            }
            if message.contains("weak_password") {
                throw AuthError.weakPassword
            }
            throw AuthError.unknown(error.localizedDescription)
        }
    }
}

extension AppUser {
    init(_ user: User) {
        self.init(id: user.id, email: user.email, isGuest: user.isAnonymous)
    }
}
