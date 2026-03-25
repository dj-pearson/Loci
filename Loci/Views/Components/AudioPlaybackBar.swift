import SwiftUI

struct AudioPlaybackBar: View {
    @Bindable var playerService: AudioPlayerService
    let audioURL: URL?
    var waveformColor: Color = Theme.primary

    @State private var isSeeking = false
    @State private var seekValue: Double = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Waveform
            AudioWaveformView(
                amplitude: playerService.isPlaying ? Float(playerService.progress) : 0,
                barCount: 50,
                barColor: waveformColor,
                maxHeight: 40
            )

            // Controls
            HStack(spacing: Theme.Spacing.md) {
                // Play/Pause button
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: playerService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(waveformColor)
                }
                .accessibilityLabel(playerService.isPlaying
                                    ? String(localized: "Pause")
                                    : String(localized: "Play"))

                VStack(spacing: 2) {
                    // Progress slider
                    Slider(
                        value: isSeeking ? $seekValue : .init(
                            get: { playerService.progress },
                            set: { _ in }
                        ),
                        in: 0...1
                    ) { editing in
                        if editing {
                            isSeeking = true
                            seekValue = playerService.progress
                        } else {
                            isSeeking = false
                            let targetTime = seekValue * playerService.duration
                            playerService.seek(to: targetTime)
                        }
                    }
                    .tint(waveformColor)

                    // Time labels
                    HStack {
                        Text(formatTime(isSeeking
                                        ? seekValue * playerService.duration
                                        : playerService.currentTime))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)

                        Spacer()

                        Text(formatTime(playerService.duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    private func togglePlayback() {
        guard let url = audioURL else { return }
        if playerService.isPlaying {
            playerService.pause()
        } else {
            playerService.play(url: url)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    AudioPlaybackBar(
        playerService: AudioPlayerService(),
        audioURL: nil
    )
    .padding()
}
