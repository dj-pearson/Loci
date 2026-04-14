import SwiftUI

struct BiometricLockView: View {
    var biometricService: BiometricLockService

    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: biometricService.biometricType.systemImageName)
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.primary)

                Text(String(localized: "Lociate is Locked"))
                    .font(Theme.Typography.title)

                Text(String(localized: "Authenticate to access your notes"))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Button {
                    Task { await unlock() }
                } label: {
                    Label(
                        String(localized: "Unlock with \(biometricService.biometricType.displayName)"),
                        systemImage: biometricService.biometricType.systemImageName
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.sm))
                }
                .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .task {
            await unlock()
        }
    }

    private func unlock() async {
        errorMessage = nil
        do {
            _ = try await biometricService.authenticate()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
