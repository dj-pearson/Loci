import SwiftUI

struct FirstLocusView: View {
    @Environment(\.modelContext) private var modelContext

    let recordViewModel: RecordViewModel
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var didSave = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if didSave {
                successState
            } else {
                recordingPrompt
            }
        }
    }

    // MARK: - Recording Prompt

    private var recordingPrompt: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.primary)

            Text(String(localized: "Look around. What's worth remembering about this spot?"))
                .font(Theme.Typography.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Text(String(localized: "A parking tip? A restaurant rec? Something you want to remember next time?"))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            if recordViewModel.isRecording {
                Text(formattedDuration)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Theme.error)

                if !recordViewModel.transcription.isEmpty {
                    Text(recordViewModel.transcription)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .padding(.horizontal, Theme.Spacing.xl)
                }
            }

            Spacer()

            RecordButton(
                isRecording: recordViewModel.isRecording,
                amplitude: recordViewModel.amplitude
            ) {
                Task {
                    if recordViewModel.isRecording {
                        await stopAndSave()
                    } else {
                        await recordViewModel.startRecording()
                    }
                }
            }

            Button(action: onSkip) {
                Text(String(localized: "I'll do this later"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 10)
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .onAppear {
            recordViewModel.modelContext = modelContext
        }
    }

    // MARK: - Success State

    private var successState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.success)

            Text(String(localized: "Your first locus!"))
                .font(Theme.Typography.largeTitle)
                .fontWeight(.bold)

            Text(String(localized: "You'll be notified when you return here."))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()

            Button(action: onComplete) {
                Text(String(localized: "Continue"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let minutes = Int(recordViewModel.recordingDuration) / 60
        let seconds = Int(recordViewModel.recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func stopAndSave() async {
        guard let result = await recordViewModel.stopRecording() else { return }

        await recordViewModel.saveLocus(
            audioURL: result.url,
            transcription: result.transcription,
            coordinate: result.coordinate,
            category: .general,
            isShared: false
        )

        withAnimation {
            didSave = true
        }
    }
}
