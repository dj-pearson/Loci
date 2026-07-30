import LocalAuthentication
import SwiftUI

/// Presents a re-authentication prompt for sensitive operations. (US-145)
/// Supports biometric authentication with password fallback.
struct ReAuthView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    let operation: SessionManager.SensitiveOperation
    let onResult: (Bool) -> Void

    @State private var password = ""
    @State private var showPasswordField = false
    @State private var errorMessage: String?
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.primary)

            Text(String(localized: "Confirm Your Identity"))
                .font(Theme.Typography.title)

            Text(String(localized: "To \(operation.rawValue), please verify your identity."))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if showPasswordField {
                VStack(spacing: Theme.Spacing.md) {
                    SecureField(String(localized: "Password"), text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.error)
                    }

                    Button {
                        Task { await verifyPassword() }
                    } label: {
                        if isAuthenticating {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            Text(String(localized: "Verify"))
                                .font(Theme.Typography.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .disabled(password.isEmpty || isAuthenticating)
                }
            } else {
                Button {
                    Task { await authenticateWithBiometrics() }
                } label: {
                    Label(String(localized: "Verify with Biometrics"), systemImage: "faceid")
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)

                Button(String(localized: "Use Password Instead")) {
                    showPasswordField = true
                }
                .font(Theme.Typography.caption)
            }

            Button(String(localized: "Cancel"), role: .cancel) {
                onResult(false)
                dismiss()
            }
            .font(Theme.Typography.body)
        }
        .padding(Theme.Spacing.lg)
        .onAppear {
            Task { await authenticateWithBiometrics() }
        }
    }

    private func authenticateWithBiometrics() async {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            showPasswordField = true
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Verify your identity to \(operation.rawValue)"
            )
            if success {
                onResult(true)
                dismiss()
            } else {
                showPasswordField = true
            }
        } catch {
            showPasswordField = true
        }
    }

    private func verifyPassword() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            // Re-authenticate via Supabase to verify password
            guard let email = try? authService.supabaseEmail else {
                errorMessage = String(localized: "Unable to verify. Please sign in again.")
                return
            }
            _ = try await SupabaseClientProvider.shared.auth.signIn(email: email, password: password)
            onResult(true)
            dismiss()
        } catch {
            errorMessage = String(localized: "Incorrect password. Please try again.")
        }
    }
}
