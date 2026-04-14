import SwiftUI

struct MicrophonePermissionView: View {
    let audioService: AudioService
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.primary)

            Text(String(localized: "Record Voice Notes"))
                .font(Theme.Typography.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(String(localized: "Loci is voice-first — tap to record, and your note is pinned to where you are. Microphone access is the core of the experience."))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    Task {
                        await audioService.requestMicrophonePermission()
                        onComplete()
                    }
                } label: {
                    Text(String(localized: "Enable Microphone"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                        .foregroundStyle(.white)
                }

                Button(action: onSkip) {
                    Text(String(localized: "Maybe Later"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }
}
