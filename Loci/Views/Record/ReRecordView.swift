import SwiftUI

/// A simplified recording view for re-recording audio on an existing locus.
/// Captures a new audio file and transcription, returning them via callbacks.
struct ReRecordView: View {
    @Bindable var recordViewModel: RecordViewModel
    let onSave: (URL, String) -> Void
    let onCancel: () -> Void

    @State private var recordingResult: (url: URL, transcription: String)?
    @State private var isFinished = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                    .ignoresSafeArea()

                if let result = recordingResult {
                    // Review state: show transcription and confirm
                    reviewView(url: result.url, transcription: result.transcription)
                } else {
                    // Recording state
                    recordingStateView
                }
            }
            .navigationTitle(String(localized: "Re-record Audio"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        recordViewModel.cancelRecording()
                        onCancel()
                    }
                }
            }
            .alert(
                String(localized: "Recording Error"),
                isPresented: .init(
                    get: { recordViewModel.errorMessage != nil },
                    set: { if !$0 { recordViewModel.clearError() } }
                )
            ) {
                Button(String(localized: "OK")) {
                    recordViewModel.clearError()
                }
            } message: {
                if let message = recordViewModel.errorMessage {
                    Text(message)
                }
            }
        }
    }

    // MARK: - Recording State

    private var recordingStateView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            // Live transcription
            transcriptionArea

            Spacer()

            // Record button
            RecordButton(
                isRecording: recordViewModel.isRecording,
                amplitude: recordViewModel.amplitude
            ) {
                Task {
                    if recordViewModel.isRecording {
                        if let result = await recordViewModel.stopRecording() {
                            recordingResult = (url: result.url, transcription: result.transcription)
                        }
                    } else {
                        await recordViewModel.startRecording()
                    }
                }
            }

            // Duration
            durationLabel

            Spacer()
                .frame(height: Theme.Spacing.xl)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .overlay {
            if recordViewModel.isPreparing {
                preparingOverlay
            }
        }
        .onChange(of: recordViewModel.didReachMaxDuration) { _, reached in
            if reached {
                Task {
                    if let result = await recordViewModel.stopRecording() {
                        recordingResult = (url: result.url, transcription: result.transcription)
                    }
                }
            }
        }
    }

    // MARK: - Review View

    private func reviewView(url: URL, transcription: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.success)

            Text(String(localized: "Recording Complete"))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.textPrimary)

            if !transcription.isEmpty {
                ScrollView {
                    Text(transcription)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                .frame(maxHeight: 200)
                .padding(.horizontal, Theme.Spacing.md)
            } else {
                Text(String(localized: "No transcription available"))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    onSave(url, transcription)
                } label: {
                    Text(String(localized: "Use This Recording"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }

                Button {
                    recordingResult = nil
                } label: {
                    Text(String(localized: "Record Again"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    // MARK: - Transcription Area

    private var transcriptionArea: some View {
        Group {
            if recordViewModel.isRecording && !recordViewModel.transcription.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(recordViewModel.transcription)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.md)
                            .id("transcriptionEnd")
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: recordViewModel.transcription) {
                        if reduceMotion {
                            proxy.scrollTo("transcriptionEnd", anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("transcriptionEnd", anchor: .bottom)
                            }
                        }
                    }
                }
                .transition(.opacity)
            } else if !recordViewModel.isRecording {
                Text(String(localized: "Tap to start recording"))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else {
                Text(String(localized: "Listening..."))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: recordViewModel.isRecording)
        .animation(.easeInOut(duration: 0.3), value: recordViewModel.transcription.isEmpty)
    }

    // MARK: - Duration Label

    private var durationLabel: some View {
        Group {
            if recordViewModel.isRecording {
                Text(formattedDuration)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                    .accessibilityLabel(String(localized: "Recording duration: \(formattedDuration)"))
            } else {
                Text(" ")
                    .font(.system(.title3, design: .monospaced))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: recordViewModel.isRecording)
    }

    // MARK: - Preparing Overlay

    private var preparingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            ProgressView(String(localized: "Preparing..."))
                .padding(Theme.Spacing.lg)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let totalSeconds = Int(recordViewModel.recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
