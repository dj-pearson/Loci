import SwiftUI
import UIKit

/// Premium hero record button (US-166).
///
/// The button is the most important interaction in Lociate, so it gets the
/// richest motion treatment in the app:
///   * Idle state: gradient fill with a breathing primary halo and a soft
///     pulsing ring driven by the ``DesignSystem.Motion.gentle`` spring.
///   * Active state: warm record gradient, an amplitude-driven ring that
///     expands in real time, and a static inner "stop" glyph that springs in.
///   * Press feedback: snappy scale-down using ``DesignSystem.Motion.snappy``
///     and a two-beat ``HapticManager.recordStartSequence`` haptic.
///   * Reduce Motion: all infinite animations fall back to static glow rings
///     and opacity-only feedback so the button remains delightful without
///     motion sickness risk.
struct RecordButton: View {
    let isRecording: Bool
    let amplitude: Float
    let action: () -> Void

    @State private var isPulsing = false
    @State private var isPressed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttonSize: CGFloat = 88
    private let maxRingExpansion: CGFloat = 52

    var body: some View {
        Button {
            if isRecording {
                HapticManager.recordStop()
            } else {
                HapticManager.recordStartSequence()
            }
            action()
        } label: {
            ZStack {
                // Outer breathing halo (idle) — premium depth cue.
                if !isRecording {
                    Circle()
                        .fill(DesignSystem.Gradients.primaryHalo)
                        .frame(width: buttonSize + 120, height: buttonSize + 120)
                        .scaleEffect(reduceMotion ? 1.0 : (isPulsing ? 1.08 : 0.96))
                        .opacity(reduceMotion ? 0.6 : (isPulsing ? 0.35 : 0.7))
                        .animation(
                            reduceMotion
                                ? nil
                                : DesignSystem.Motion.gentle.repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                        .allowsHitTesting(false)
                }

                // Amplitude ring (recording state).
                if isRecording {
                    Circle()
                        .stroke(
                            DesignSystem.Gradients.record,
                            lineWidth: 4
                        )
                        .frame(width: amplitudeRingSize, height: amplitudeRingSize)
                        .opacity(reduceMotion
                                 ? Double(min(max(amplitude, 0.25), 1.0))
                                 : 0.85)
                        .animation(reduceMotion ? nil : DesignSystem.Motion.amplitude,
                                   value: amplitude)
                }

                // Main circle with gradient fill + layered elevation.
                Circle()
                    .fill(isRecording
                          ? DesignSystem.Gradients.record
                          : DesignSystem.Gradients.primary)
                    .frame(width: buttonSize, height: buttonSize)
                    .elevation(.level3)
                    .overlay(
                        // Glossy top highlight for premium feel.
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.45),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                            .frame(width: buttonSize, height: buttonSize)
                    )
                    .animation(reduceMotion ? nil : DesignSystem.Motion.smooth,
                               value: isRecording)

                // Icon — mic (idle) ↔ stop square (recording).
                ZStack {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .opacity(isRecording ? 0 : 1)
                        .scaleEffect(isRecording ? 0.4 : 1)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .opacity(isRecording ? 1 : 0)
                        .scaleEffect(isRecording ? 1 : 0.4)
                }
                .animation(reduceMotion ? nil : DesignSystem.Motion.bouncy,
                           value: isRecording)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(reduceMotion ? nil : DesignSystem.Motion.snappy, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(isRecording
            ? String(localized: "Stop recording")
            : String(localized: "Record voice note"))
        .accessibilityHint(isRecording
            ? String(localized: "Double tap to stop recording")
            : String(localized: "Double tap to start recording"))
        .accessibilityAddTraits(.isButton)
        .onAppear {
            if !isRecording {
                isPulsing = true
            }
        }
        .onChange(of: isRecording) { _, newValue in
            isPulsing = !newValue
        }
    }

    // MARK: - Computed Properties

    /// Maps amplitude (0...1) to a ring diameter that expands around the
    /// button. Clamped to ``maxRingExpansion`` so the ring never overflows
    /// its container regardless of input spikes.
    private var amplitudeRingSize: CGFloat {
        let normalized = CGFloat(min(max(amplitude, 0), 1))
        let base = buttonSize + 18
        return base + maxRingExpansion * normalized
    }
}

#Preview("Idle") {
    RecordButton(isRecording: false, amplitude: 0) {}
        .padding(60)
        .background(Theme.background)
}

#Preview("Recording") {
    RecordButton(isRecording: true, amplitude: 0.6) {}
        .padding(60)
        .background(Theme.background)
}
