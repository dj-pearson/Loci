import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showResetPassword = false
    @State private var showError = false
    // US-147: Password visibility toggle
    @State private var isPasswordVisible = false
    // US-147: Error shake animation
    @State private var errorShakeOffset: CGFloat = 0

    @FocusState private var focusedField: SignInField?

    private enum SignInField: Hashable {
        case email, password
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.primary)

                        Text("Sign in to Lociate")
                            .font(Theme.Typography.largeTitle)

                        Text("Sync your notes across devices and share with family.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Theme.Spacing.xl)

                    // Apple Sign In
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(Theme.CornerRadius.medium)
                    .disabled(authService.isLoading)

                    dividerRow

                    // Email/Password Form
                    VStack(spacing: Theme.Spacing.md) {
                        // US-147: Auto-focus email field
                        TextField(String(localized: "Email"), text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .disabled(authService.isLoading)

                        // US-147: Password field with visibility toggle
                        HStack {
                            Group {
                                if isPasswordVisible {
                                    TextField(String(localized: "Password"), text: $password)
                                        .textContentType(.password)
                                } else {
                                    SecureField(String(localized: "Password"), text: $password)
                                        .textContentType(.password)
                                }
                            }
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submitSignIn() }
                            .disabled(authService.isLoading)

                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 24, height: 24)
                            }
                            .disabled(authService.isLoading)
                        }
                        .textFieldStyle(.roundedBorder)

                        // US-143: Lockout indicator
                        if authService.loginAttemptTracker.isLockedOut {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(Theme.error)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Account temporarily locked")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.error)
                                    Text("Try again in \(authService.loginAttemptTracker.formattedTime(authService.loginAttemptTracker.remainingLockoutSeconds))")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(Theme.Spacing.sm)
                            .background(Theme.error.opacity(0.1))
                            .cornerRadius(Theme.CornerRadius.small)
                        }

                        // US-143: Failed attempt warning (before lockout)
                        if authService.loginAttemptTracker.failedAttemptCount > 0 && !authService.loginAttemptTracker.isLockedOut {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.warning)
                                Text("\(authService.loginAttemptTracker.failedAttemptCount) failed attempt(s)")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.warning)
                                Spacer()
                            }
                            .padding(Theme.Spacing.sm)
                            .background(Theme.warning.opacity(0.1))
                            .cornerRadius(Theme.CornerRadius.small)
                            // US-147: Shake animation on error
                            .offset(x: errorShakeOffset)
                        }

                        Button {
                            submitSignIn()
                        } label: {
                            if authService.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            } else {
                                Text("Sign In")
                                    .font(Theme.Typography.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .disabled(email.isEmpty || password.isEmpty || authService.isLoading || authService.loginAttemptTracker.isLockedOut)
                    }

                    // Links
                    VStack(spacing: Theme.Spacing.sm) {
                        Button(String(localized: "Forgot Password?")) {
                            showResetPassword = true
                        }
                        .font(Theme.Typography.caption)
                        .disabled(authService.isLoading)

                        // US-143: Password reset suggestion after many failures
                        if authService.loginAttemptTracker.shouldSuggestPasswordReset {
                            Text("Having trouble? Try resetting your password.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.primary)
                        }

                        HStack {
                            Text("Don't have an account?")
                                .foregroundStyle(Theme.textSecondary)
                            Button(String(localized: "Sign Up")) {
                                showSignUp = true
                            }
                            .disabled(authService.isLoading)
                        }
                        .font(Theme.Typography.body)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .disabled(authService.isLoading)
                }
            }
            .sheet(isPresented: $showSignUp) {
                SignUpView()
            }
            .alert(String(localized: "Reset Password"), isPresented: $showResetPassword) {
                TextField(String(localized: "Email"), text: $email)
                Button(String(localized: "Send Reset Link")) {
                    Task {
                        try? await authService.resetPassword(email: email)
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("Enter your email to receive a password reset link.")
            }
            .alert(String(localized: "Error"), isPresented: $showError) {
                Button(String(localized: "OK")) {}
            } message: {
                Text(authService.errorMessage ?? String(localized: "An error occurred."))
            }
            .onChange(of: authService.isAuthenticated) { _, isAuth in
                if isAuth {
                    // US-147: Dismiss keyboard before dismiss animation
                    focusedField = nil
                    HapticManager.saveSuccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        dismiss()
                    }
                }
            }
            // US-147: Auto-focus email field on appear
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .email
                }
            }
        }
    }

    private var dividerRow: some View {
        HStack {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.textSecondary.opacity(0.3))
            Text("or")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.textSecondary.opacity(0.3))
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            Task {
                do {
                    try await authService.signInWithApple(credential: credential)
                } catch {
                    HapticManager.delete()
                    showError = true
                }
            }
        case .failure:
            HapticManager.delete()
            showError = true
        }
    }

    // US-147: Submit via button or keyboard return key
    private func submitSignIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        guard !authService.isLoading, !authService.loginAttemptTracker.isLockedOut else { return }
        // Dismiss keyboard before async work
        focusedField = nil
        Task { await signInWithEmail() }
    }

    private func signInWithEmail() async {
        do {
            try await authService.signIn(email: email, password: password)
        } catch {
            // US-147: Haptic error feedback + shake animation
            HapticManager.delete()
            triggerShakeAnimation()
            showError = true
        }
    }

    // US-147: Error shake animation
    private func triggerShakeAnimation() {
        withAnimation(.default) { errorShakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.default) { errorShakeOffset = -10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.default) { errorShakeOffset = 8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.default) { errorShakeOffset = -5 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.default) { errorShakeOffset = 0 }
        }
    }
}

struct SignUpView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var showError = false
    // US-147: Password visibility toggles
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false

    @FocusState private var focusedField: SignUpField?

    private enum SignUpField: Hashable {
        case displayName, email, password, confirmPassword
    }

    /// US-144: Password meets minimum requirements (fair or above).
    private var passwordMeetsMinimum: Bool {
        PasswordValidator.validate(password).requirements.meetsMinimum
    }

    /// US-144: Passwords match.
    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    private var canSubmit: Bool {
        !email.isEmpty && !displayName.isEmpty && passwordMeetsMinimum && passwordsMatch && !authService.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.primary)

                        Text("Create Account")
                            .font(Theme.Typography.title)
                    }
                    .padding(.top, Theme.Spacing.xl)

                    VStack(spacing: Theme.Spacing.md) {
                        // US-147: Return key flows display name → email → password → confirm → submit
                        TextField(String(localized: "Display Name"), text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                            .focused($focusedField, equals: .displayName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }
                            .disabled(authService.isLoading)

                        TextField(String(localized: "Email"), text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .disabled(authService.isLoading)

                        // US-147: Password with visibility toggle
                        HStack {
                            Group {
                                if isPasswordVisible {
                                    TextField(String(localized: "Password"), text: $password)
                                        .textContentType(.newPassword)
                                } else {
                                    SecureField(String(localized: "Password"), text: $password)
                                        .textContentType(.newPassword)
                                }
                            }
                            .focused($focusedField, equals: .password)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .confirmPassword }
                            .disabled(authService.isLoading)

                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 24, height: 24)
                            }
                            .disabled(authService.isLoading)
                        }
                        .textFieldStyle(.roundedBorder)

                        // US-144: Password strength indicator
                        if !password.isEmpty {
                            PasswordStrengthView(password: password)
                        }

                        // US-147: Confirm password with visibility toggle and match indicator
                        HStack {
                            Group {
                                if isConfirmPasswordVisible {
                                    TextField(String(localized: "Confirm Password"), text: $confirmPassword)
                                        .textContentType(.newPassword)
                                } else {
                                    SecureField(String(localized: "Confirm Password"), text: $confirmPassword)
                                        .textContentType(.newPassword)
                                }
                            }
                            .focused($focusedField, equals: .confirmPassword)
                            .submitLabel(.go)
                            .onSubmit { submitSignUp() }
                            .disabled(authService.isLoading)

                            Button {
                                isConfirmPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isConfirmPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 24, height: 24)
                            }
                            .disabled(authService.isLoading)

                            if !confirmPassword.isEmpty {
                                Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(passwordsMatch ? Theme.success : Theme.error)
                                    .font(.system(size: 18))
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords do not match")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            submitSignUp()
                        } label: {
                            if authService.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            } else {
                                Text("Create Account")
                                    .font(Theme.Typography.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .disabled(!canSubmit)
                    }

                    HStack {
                        Text("Already have an account?")
                            .foregroundStyle(Theme.textSecondary)
                        Button(String(localized: "Sign In")) { dismiss() }
                            .disabled(authService.isLoading)
                    }
                    .font(Theme.Typography.body)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .disabled(authService.isLoading)
                }
            }
            .alert(String(localized: "Error"), isPresented: $showError) {
                Button(String(localized: "OK")) {}
            } message: {
                Text(authService.errorMessage ?? String(localized: "An error occurred."))
            }
            .onChange(of: authService.isAuthenticated) { _, isAuth in
                if isAuth {
                    focusedField = nil
                    HapticManager.saveSuccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .displayName
                }
            }
        }
    }

    // US-147: Submit via button or keyboard return key
    private func submitSignUp() {
        guard canSubmit else { return }
        focusedField = nil
        Task { await signUp() }
    }

    private func signUp() async {
        // US-144: Validate password strength before submitting
        guard passwordMeetsMinimum else {
            authService.errorMessage = AuthError.passwordTooWeak.localizedDescription
            HapticManager.delete()
            showError = true
            return
        }
        guard passwordsMatch else {
            authService.errorMessage = AuthError.passwordsDoNotMatch.localizedDescription
            HapticManager.delete()
            showError = true
            return
        }
        do {
            try await authService.signUp(email: email, password: password, displayName: displayName)
        } catch {
            HapticManager.delete()
            showError = true
        }
    }
}
