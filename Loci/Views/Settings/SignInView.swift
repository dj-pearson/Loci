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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.primary)

                        Text("Sign in to Loci")
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

                    dividerRow

                    // Email/Password Form
                    VStack(spacing: Theme.Spacing.md) {
                        TextField(String(localized: "Email"), text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        SecureField(String(localized: "Password"), text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)

                        Button {
                            Task { await signInWithEmail() }
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
                        .disabled(email.isEmpty || password.isEmpty || authService.isLoading)
                    }

                    // Links
                    VStack(spacing: Theme.Spacing.sm) {
                        Button(String(localized: "Forgot Password?")) {
                            showResetPassword = true
                        }
                        .font(Theme.Typography.caption)

                        HStack {
                            Text("Don't have an account?")
                                .foregroundStyle(Theme.textSecondary)
                            Button(String(localized: "Sign Up")) {
                                showSignUp = true
                            }
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
                if isAuth { dismiss() }
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
                    showError = true
                }
            }
        case .failure:
            showError = true
        }
    }

    private func signInWithEmail() async {
        do {
            try await authService.signIn(email: email, password: password)
        } catch {
            showError = true
        }
    }
}

struct SignUpView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showError = false

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
                        TextField(String(localized: "Display Name"), text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)

                        TextField(String(localized: "Email"), text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        SecureField(String(localized: "Password (8+ characters)"), text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)

                        Button {
                            Task { await signUp() }
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
                        .disabled(email.isEmpty || password.isEmpty || displayName.isEmpty || authService.isLoading)
                    }

                    HStack {
                        Text("Already have an account?")
                            .foregroundStyle(Theme.textSecondary)
                        Button(String(localized: "Sign In")) { dismiss() }
                    }
                    .font(Theme.Typography.body)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .alert(String(localized: "Error"), isPresented: $showError) {
                Button(String(localized: "OK")) {}
            } message: {
                Text(authService.errorMessage ?? String(localized: "An error occurred."))
            }
            .onChange(of: authService.isAuthenticated) { _, isAuth in
                if isAuth { dismiss() }
            }
        }
    }

    private func signUp() async {
        do {
            try await authService.signUp(email: email, password: password, displayName: displayName)
        } catch {
            showError = true
        }
    }
}
