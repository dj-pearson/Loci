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

    /// Tracks failed login attempts for brute force protection (US-143).
    let loginAttemptTracker = LoginAttemptTracker()

    /// Manages session lifecycle: inactivity timeout, re-auth, token refresh (US-145).
    let sessionManager = SessionManager()

    /// US-149: Security audit logger for authentication events.
    private let auditLogger = SecurityAuditLogger.shared

    /// Set this from the app's model context to enable audit logging to SwiftData.
    var auditModelContext: ModelContext?

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

                // US-195: a device token obtained before the user had a session
                // is queued rather than dropped; bind it to the account now.
                if event == .signedIn, session != nil {
                    await PushRegistrationService.shared.handleSignIn()
                }
            }
        }
    }

    // MARK: - Session Restore

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session

            // US-145: Check session inactivity timeout
            guard sessionManager.checkSessionValidity() else {
                // US-149: Audit log session expiry
                auditLogger.log(event: .sessionExpired, modelContext: auditModelContext)
                await setError(sessionManager.sessionExpiryReason?.message ?? "")
                try? await signOut()
                return
            }

            sessionManager.recordActivity()
            sessionManager.resetTokenRefreshFailures()

            await MainActor.run {
                self.isAuthenticated = true
            }
            _ = session // Session exists, user is authenticated
        } catch {
            // US-145: Track token refresh failures
            if sessionManager.recordTokenRefreshFailure() {
                await setError(SessionManager.ExpiryReason.tokenRefreshFailed.message)
            }
            await MainActor.run {
                self.isAuthenticated = false
            }
        }
    }

    // MARK: - Apple Sign In (US-070, US-175)

    /// Signs in using an Apple ID credential. US-175: the `rawNonce` passed in must
    /// match the SHA256 hash that was set on the original ASAuthorizationAppleIDRequest.
    /// Supabase verifies the hash on the Apple-issued identity token, preventing replay
    /// of a stolen identity token on a different authentication attempt.
    func signInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }
        guard let rawNonce, !rawNonce.isEmpty else {
            // US-175: refuse credentials that were not bound to a nonce — otherwise the
            // token is replayable. Caller must always provide a fresh random nonce.
            throw AuthError.invalidCredential
        }

        await setLoading(true)
        defer { Task { await setLoading(false) } }

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString,
                    nonce: rawNonce
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

        // US-144: Enforce password complexity requirements
        let validation = PasswordValidator.validate(password)
        guard validation.requirements.meetsMinimum else { throw AuthError.passwordTooWeak }

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
                // US-149: Audit log sign-up
                auditLogger.log(event: .signUp, email: email, modelContext: auditModelContext)

                await updateLocalProfile(
                    authId: UUID(uuidString: session.user.id.uuidString) ?? UUID(),
                    displayName: sanitizedName,
                    email: email
                )
            }
        } catch {
            // US-150: Generic error to prevent email enumeration.
            // Don't reveal whether the email already exists.
            await setError(String(localized: "If this email is available, you will receive a confirmation."))
            throw error
        }
    }

    func signIn(email: String, password: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }

        // US-143: Check brute force lockout before attempting
        if let lockoutMessage = loginAttemptTracker.checkAllowed(email: email) {
            await setError(lockoutMessage)
            throw AuthError.rateLimited
        }

        await setLoading(true)
        defer { Task { await setLoading(false) } }

        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )

            // US-143: Reset attempt counter on success
            loginAttemptTracker.recordSuccess(email: email)

            // US-145: Record session activity and reset token failures
            sessionManager.recordActivity()
            sessionManager.resetTokenRefreshFailures()

            // US-149: Audit log sign-in success
            auditLogger.log(event: .signInSuccess, email: email, modelContext: auditModelContext)

            await updateLocalProfile(
                authId: UUID(uuidString: session.user.id.uuidString) ?? UUID(),
                displayName: nil,
                email: email
            )
        } catch {
            // US-143: Record failed attempt (only for credential errors, not network)
            let message = error.localizedDescription.lowercased()
            if !message.contains("network") && !message.contains("connection") {
                loginAttemptTracker.recordFailure(email: email)
            }

            // US-149: Audit log sign-in failure
            auditLogger.log(event: .signInFailure, email: email, modelContext: auditModelContext)

            await setError(mapAuthError(error))
            throw error
        }
    }

    /// US-150: Always shows success regardless of whether the email exists,
    /// to prevent account enumeration attacks.
    func resetPassword(email: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }

        await setLoading(true)
        defer { Task { await setLoading(false) } }

        // US-149: Audit log password reset request
        auditLogger.log(event: .passwordResetRequest, email: email, modelContext: auditModelContext)

        // US-150: Fire-and-forget — always show success to user
        try? await supabase.auth.resetPasswordForEmail(email)
        // Intentionally does not throw or show error even if email doesn't exist
    }

    // MARK: - Sign Out & Delete (US-072)

    func signOut() async throws {
        // US-149: Audit log sign-out
        let email = supabaseEmail
        auditLogger.log(event: .signOut, email: email, modelContext: auditModelContext)

        // US-195: clear the device's APNs token *before* dropping the session —
        // afterwards there is no authenticated row to update, and a stale token
        // would keep delivering another account's digests to this device.
        await PushRegistrationService.shared.handleSignOut()

        try await supabase.auth.signOut()
        // US-145: Clear all session data on sign out
        sessionManager.clearSession()
        await MainActor.run {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }

    func deleteAccount(modelContext: ModelContext) async throws {
        // US-149: Audit log account deletion
        let email = supabaseEmail
        auditLogger.log(event: .accountDeleted, email: email, modelContext: auditModelContext)

        // Call server-side deletion RPC
        try await supabase.rpc("delete_user_account").execute()

        // US-195: the users row (and its apns_token) is already gone, so only the
        // local token state needs dropping.
        PushRegistrationService.shared.handleAccountDeleted()

        // Sign out locally
        try await signOut()

        // Clear local user profile
        if let profile = currentUser {
            modelContext.delete(profile)
            try? modelContext.save()
        }
    }

    // MARK: - Session Helpers

    /// The current authenticated user's email (for re-auth flows, US-145).
    ///
    /// Reads `currentUser`, which is a synchronous non-isolated accessor over the
    /// cached session. The previous `get throws { try supabase.auth.session… }` did not
    /// compile: `session` is an `async` property, so it cannot be reached from a
    /// synchronous getter. Nothing here throws any more, so callers no longer use `try?`.
    var supabaseEmail: String? {
        supabase.auth.currentUser?.email
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
    ///
    /// NOTE: this function currently has no callers anywhere in the app.
    ///
    /// Uses the synchronous `currentUser` accessor; the previous
    /// `try? supabase.auth.session.user.id` did not compile because `session` is async
    /// and this function is not.
    func syncLocalProfile(modelContext: ModelContext) {
        guard let authId = supabase.auth.currentUser?.id else { return }

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

    /// Surfaces a client-side validation failure through the same channel as server
    /// errors, so a view has one place to read from.
    ///
    /// `errorMessage` is deliberately `private(set)` — only this service decides what
    /// its error state is. SignInView was assigning to it directly, which does not
    /// compile; this is the narrow, intentional way in.
    @MainActor
    func reportValidationError(_ message: String) {
        setError(message)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
        return email.wholeMatch(of: regex) != nil
    }

    /// US-150: Maps auth errors to user-facing messages without revealing
    /// whether an email exists in the system (prevents account enumeration).
    private func mapAuthError(_ error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("network") || message.contains("connection") {
            return String(localized: "Network error. Please check your connection and try again.")
        }
        // US-150: Generic message for all credential errors — never say "email not found"
        // or "account already exists" to prevent email enumeration.
        return String(localized: "Invalid email or password.")
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredential
    case invalidEmail
    case passwordTooShort
    case passwordTooWeak
    case passwordsDoNotMatch
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            String(localized: "Invalid Apple ID credential. Please try again.")
        case .invalidEmail:
            String(localized: "Please enter a valid email address.")
        case .passwordTooShort:
            String(localized: "Password must be at least 8 characters.")
        case .passwordTooWeak:
            String(localized: "Password does not meet security requirements.")
        case .passwordsDoNotMatch:
            String(localized: "Passwords do not match.")
        case .rateLimited:
            String(localized: "Too many attempts. Please wait before trying again.")
        }
    }
}
