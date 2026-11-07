import AuthenticationServices
import CryptoKit
import SwiftUI

struct WelcomeView: View {
    @State private var authMode: EmailAuthView.Mode?

    var body: some View {
        VStack(spacing: PlantySpacing.l) {
            HStack(spacing: PlantySpacing.s) {
                Image(systemName: "leaf.fill").foregroundStyle(Color.plantyForest)
                Text("Planty").font(.plantyTitle).foregroundStyle(Color.plantyForest)
            }
            .accessibilityElement(children: .combine)

            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color.plantyMint)
                PlantAvatarView(mood: .happy, growthStage: .mature)
                    .padding(PlantySpacing.xl)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: PlantySpacing.s) {
                Text("Your plants.\nYour little world.")
                    .font(.plantyLargeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.plantyTextPrimary)
                Text("Take care of your plants, watch them grow and build your own living garden.")
                    .font(.plantyBody)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.plantyTextSecondary)
            }

            VStack(spacing: PlantySpacing.m - 4) {
                Button("Get started") { authMode = .signUp }
                    .buttonStyle(.plantyPrimary)
                Button("I already have an account") { authMode = .signIn }
                    .buttonStyle(.plantySecondary)
            }
        }
        .padding(.horizontal, PlantySpacing.l)
        .padding(.vertical, PlantySpacing.m)
        .plantyScreenBackground()
        .sheet(item: $authMode) { mode in
            EmailAuthView(mode: mode)
                .presentationDetents([.large])
        }
    }
}

struct EmailAuthView: View {
    enum Mode: String, Identifiable { case signUp, signIn; var id: String { rawValue } }

    let mode: Mode
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var confirmationSent = false
    @State private var appleNonce = ""

    private var canSubmit: Bool {
        email.contains("@") && password.count >= (mode == .signUp ? 8 : 1) && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlantySpacing.m) {
                    SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
                        appleNonce = Nonce.random()
                        request.requestedScopes = [.email]
                        request.nonce = Nonce.sha256(appleNonce)
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: PlantyRadius.button, style: .continuous))

                    Text("or with email")
                        .font(.plantyCaption)
                        .foregroundStyle(Color.plantyTextSecondary)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: PlantySpacing.s) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Divider()
                        SecureField("Password", text: $password)
                            .textContentType(mode == .signUp ? .newPassword : .password)
                    }
                    .plantyCard()

                    if mode == .signUp {
                        Text("At least 8 characters.")
                            .font(.plantyCaption)
                            .foregroundStyle(Color.plantyTextSecondary)
                    }

                    if let error = session.lastError {
                        Text(error)
                            .font(.plantyCaption)
                            .foregroundStyle(Color.plantyCritical)
                            .accessibilityLabel(Text("Error: \(error)"))
                    }
                    if confirmationSent {
                        Text("Check your inbox and open the link we sent to confirm your email. Then sign in.")
                            .font(.plantyCaption)
                            .foregroundStyle(Color.plantyForest)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking { ProgressView().tint(Color.plantyOnForest) }
                        else { Text(mode == .signUp ? "Create account" : "Sign in") }
                    }
                    .buttonStyle(.plantyPrimary)
                    .disabled(!canSubmit)

                    if mode == .signUp {
                        VStack(alignment: .leading, spacing: PlantySpacing.xs) {
                            Button("Continue as guest") {
                                Task {
                                    isWorking = true
                                    await session.continueAsGuest()
                                    isWorking = false
                                }
                            }
                            .font(.plantyHeadline)
                            .disabled(isWorking)
                            Text("Your garden stays on this account only. If you delete the app before adding Apple or email in Profile, your garden is lost.")
                                .font(.plantyCaption)
                                .foregroundStyle(Color.plantyTextSecondary)
                        }
                        .padding(.top, PlantySpacing.s)
                    }
                }
                .padding(PlantySpacing.l)
            }
            .plantyScreenBackground()
            .navigationTitle(mode == .signUp ? "Create your garden" : "Welcome back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { session.lastError = nil }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .signIn:
            await session.signIn(email: trimmed, password: password)
        case .signUp:
            confirmationSent = await session.signUp(email: trimmed, password: password)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                session.lastError = AuthError.appleTokenMissing.localizedDescription
                return
            }
            Task {
                isWorking = true
                await session.signInWithApple(idToken: token, nonce: appleNonce)
                isWorking = false
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            session.lastError = error.localizedDescription
        }
    }
}

/// Nonce for Sign in with Apple: Apple gets the SHA-256 hash, Supabase gets the raw value.
enum Nonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset[Int(generator.next() % UInt64(charset.count))] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
