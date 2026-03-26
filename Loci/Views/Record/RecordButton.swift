import SwiftUI
import UIKit

struct RecordButton: View {
    let isRecording: Bool
    let amplitude: Float
    let action: () -> Void

    @State private var isPulsing = false
    @State private var isPressed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttonSize: CGFloat = 80
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        Button {
            feedbackGenerator.impactOccurred()
            action()
        } label: {
            ZStack {
                // Amplitude ring (recording state only)
                if isRecording {
                    if reduceMotion {
                        // Static ring with opacity mapped to amplitude
                        Circle()
                            .stroke(Theme.error.opacity(Double(min(max(amplitude, 0.2), 1))), lineWidth: 4)
                            .frame(width: buttonSize + 20, height: buttonSize + 20)
                    } else {
                        Circle()
                            .stroke(Theme.error.opacity(0.3), lineWidth: 4)
                            .frame(width: amplitudeRingSize, height: amplitudeRingSize)
                            .animation(.easeOut(duration: 0.1), value: amplitude)
                    }
                }

                // Pulse ring (idle state only) — replaced with static glow for reduce motion
                if !isRecording && !reduceMotion {
                    Circle()
                        .fill(Theme.primary.opacity(0.15))
                        .frame(width: buttonSize + 20, height: buttonSize + 20)
                        .scaleEffect(isPulsing ? 1.15 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                } else if !isRecording {
                    // Static subtle glow ring for reduce motion
                    Circle()
                        .fill(Theme.primary.opacity(0.12))
                        .frame(width: buttonSize + 20, height: buttonSize + 20)
                }

                // Main circle
                Circle()
                    .fill(isRecording ? Theme.error : Theme.primary)
                    .frame(width: buttonSize, height: buttonSize)
                    .shadow(color: (isRecording ? Theme.error : Theme.primary).opacity(0.4), radius: 8, y: 4)

                // Icon
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .accessibilityLabel(isRecording
            ? String(localized: "Stop recording")
            : String(localized: "Record voice note"))
        .accessibilityHint(isRecording
            ? String(localized: "Double tap to stop recording")
            : String(localized: "Double tap to start recording"))
        .accessibilityAddTraits(.isButton)
        .onAppear {
            feedbackGenerator.prepare()
            if !isRecording {
                isPulsing = true
            }
        }
        .onChange(of: isRecording) { _, newValue in
            isPulsing = !newValue
        }
    }

    // MARK: - Computed Properties

    /// Maps amplitude (0...1) to a ring diameter that expands around the button.
    private var amplitudeRingSize: CGFloat {
        let normalized = CGFloat(min(max(amplitude, 0), 1))
        let minSize = buttonSize + 16
        let maxSize = buttonSize + 48
        return minSize + (maxSize - minSize) * normalized
    }
}

#Preview("Idle") {
    RecordButton(isRecording: false, amplitude: 0) {}
        .padding()
}

#Preview("Recording") {
    RecordButton(isRecording: true, amplitude: 0.6) {}
        .padding()
}
