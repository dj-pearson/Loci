import AuthenticationServices
import Foundation
import Supabase
import SwiftData

@Observable
final class AuthService {
    // MARK: - Published State

    private(set) var isAuthenticated = false
    private(set) var currentUser: UserProfile?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let supabase = SupabaseClientProvider.shared
    private var authStateTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        observeAuthState()
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Auth State Observation

    private func observeAuthState() {
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.supabase.auth.authStateChanges {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    switch event {
                    case .signedIn, .tokenRefreshed:
                        self.isAuthenticated = session != nil
                    case .signedOut:
                        self.isAuthenticated = false
                        self.currentUser = nil
                    default:
                        break
                    }
                }
            }
        }
    }

    // MARK: - Session Restore

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            await MainActor.run {
                self.isAuthenticated = true
            }
            _ = session // Session exists, user is authenticated
        } catch {
            await MainActor.run {
                self.isAuthenticated = false
            }
        }
    }

    // MARK: - Apple Sign In (US-070)

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }

        await setLoading(true)
        defer { Task { await setLoading(false) } }

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString
                )
            )

            await updateLocalProfile(
                authId: UUID(uuidString: session.user.id.uuidString) ?? UUID(),
                displayName: credential.fullName.flatMap { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) },
                email: credential.email
            )
        } catch {
            await setError(mapAuthError(error))
            throw error
        }
    }

    // MARK: - Email/Password (US-071)

    func signUp(email: String, password: String, displayName: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        guard password.count >= 8 else { throw AuthError.passwordTooShort }

        await setLoading(true)
        defer { Task { await setLoading(false) } }

        do {
            let sanitizedName = InputSanitizer.sanitizeDisplayName(displayName)
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["display_name": .string(sanitizedName)]
            )

            if let session = response.session {
                await updateLocalProfile(
                    authId: UUID(uuidString: session.user.id.uuidString) ?? UUID(),
                    displayName: sanitizedName,
                    email: email
                )
            }
        } catch {
            await setError(mapAuthError(error))
            throw error
        }
    }

    func signIn(email: String, password: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }

        await setLoading(true)
        defer { Task { await setLoading(false) } }

        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )

            await updateLocalProfile(
                authId: UUID(uuidString: session.user.id.uuidString) ?? UUID(),
                displayName: nil,
                email: email
            )
        } catch {
            await setError(mapAuthError(error))
            throw error
        }
    }

    func resetPassword(email: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }

        await setLoading(true)
        defer { Task { await setLoading(false) } }

        do {
            try await supabase.auth.resetPasswordForEmail(email)
        } catch {
            await setError(mapAuthError(error))
            throw error
        }
    }

    // MARK: - Sign Out & Delete (US-072)

    func signOut() async throws {
        try await supabase.auth.signOut()
        await MainActor.run {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }

    func deleteAccount(modelContext: ModelContext) async throws {
        // Call server-side deletion RPC
        try await supabase.rpc("delete_user_account").execute()

        // Sign out locally
        try await signOut()

        // Clear local user profile
        if let profile = currentUser {
            modelContext.delete(profile)
            try? modelContext.save()
        }
    }

    // MARK: - Helpers

    private func updateLocalProfile(authId: UUID, displayName: String?, email: String?) async {
        await MainActor.run {
            if let existing = currentUser {
                existing.authId = authId
                if let name = displayName, !name.isEmpty {
                    existing.displayName = InputSanitizer.sanitizeDisplayName(name)
                }
            } else {
                let name = InputSanitizer.sanitizeDisplayName(displayName ?? email ?? String(localized: "User"))
                currentUser = UserProfile(authId: authId, displayName: name)
            }
            isAuthenticated = true
            errorMessage = nil
        }
    }

    /// Syncs the local UserProfile with SwiftData after auth.
    func syncLocalProfile(modelContext: ModelContext) {
        guard let authId = try? supabase.auth.session.user.id else { return }

        let authIdString = authId.uuidString
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.authId?.uuidString == authIdString }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            currentUser = existing
        } else if let profile = currentUser {
            modelContext.insert(profile)
            try? modelContext.save()
        }
    }

    @MainActor
    private func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    @MainActor
    private func setError(_ message: String) {
        errorMessage = message
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
        return email.wholeMatch(of: regex) != nil
    }

    private func mapAuthError(_ error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("invalid") || message.contains("credentials") {
            return String(localized: "Invalid email or password. Please try again.")
        }
        if message.contains("already") || message.contains("exists") {
            return String(localized: "An account with this email already exists.")
        }
        if message.contains("network") || message.contains("connection") {
            return String(localized: "Network error. Please check your connection and try again.")
        }
        return String(localized: "Authentication failed. Please try again.")
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredential
    case invalidEmail
    case passwordTooShort

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            String(localized: "Invalid Apple ID credential. Please try again.")
        case .invalidEmail:
            String(localized: "Please enter a valid email address.")
        case .passwordTooShort:
            String(localized: "Password must be at least 8 characters.")
        }
    }
}
