import SwiftUI

/// A view that displays an animated waveform visualization driven by audio amplitude.
///
/// Works in both recording (live amplitude) and playback (progress-based) contexts.
/// Falls back to a simple opacity pulse when Reduce Motion is enabled.
struct AudioWaveformView: View {
    /// Current amplitude value in the range 0.0...1.0.
    var amplitude: Float

    /// Number of bars to display. Default is 30.
    var barCount: Int = 30

    /// Color of the waveform bars. Default is the theme primary color.
    var barColor: Color = Theme.primary

    /// Maximum height of the tallest bar. Default is 60 points.
    var maxHeight: CGFloat = 60

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var barHeights: [CGFloat] = []
    @State private var pulseOpacity: Double = 0.4

    var body: some View {
        if reduceMotion {
            reducedMotionView
        } else {
            waveformBars
        }
    }

    // MARK: - Waveform Bars

    private var waveformBars: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: barWidth, height: barHeight(for: index))
            }
        }
        .frame(height: maxHeight)
        .onChange(of: amplitude) {
            withAnimation(.easeOut(duration: 0.08)) {
                updateBarHeights()
            }
        }
        .onAppear {
            initializeBarHeights()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Audio waveform"))
        .accessibilityValue(amplitudeAccessibilityValue)
    }

    // MARK: - Reduced Motion Fallback

    private var reducedMotionView: some View {
        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
            .fill(barColor.opacity(pulseOpacity))
            .frame(height: maxHeight * 0.4)
            .onChange(of: amplitude) {
                let normalizedAmplitude = Double(clampedAmplitude)
                pulseOpacity = 0.2 + normalizedAmplitude * 0.6
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Audio level indicator"))
            .accessibilityValue(amplitudeAccessibilityValue)
    }

    // MARK: - Bar Height Computation

    private func barHeight(for index: Int) -> CGFloat {
        guard !barHeights.isEmpty, index < barHeights.count else {
            return minBarHeight
        }
        return barHeights[index]
    }

    private func initializeBarHeights() {
        barHeights = Array(repeating: minBarHeight, count: barCount)
    }

    private func updateBarHeights() {
        let clamped = CGFloat(clampedAmplitude)

        barHeights = (0..<barCount).map { index in
            guard clamped > 0.01 else { return minBarHeight }

            // Create a wave pattern using sine with phase offset per bar
            let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
            let phase = normalizedIndex * .pi * 2
            let wave = (sin(phase + Double.random(in: -0.5...0.5)) + 1.0) / 2.0

            // Blend between minimum height and amplitude-scaled height
            let amplitudeHeight = minBarHeight + (maxHeight - minBarHeight) * clamped * CGFloat(wave)
            return max(minBarHeight, amplitudeHeight)
        }
    }

    // MARK: - Layout Constants

    private var minBarHeight: CGFloat {
        max(4, maxHeight * 0.06)
    }

    private var barWidth: CGFloat {
        3
    }

    private var barSpacing: CGFloat {
        2
    }

    // MARK: - Helpers

    private var clampedAmplitude: Float {
        min(max(amplitude, 0), 1)
    }

    private var amplitudeAccessibilityValue: String {
        let percentage = Int(clampedAmplitude * 100)
        return String(localized: "\(percentage) percent")
    }
}

// MARK: - Previews

#Preview("Silent") {
    AudioWaveformView(amplitude: 0)
        .padding()
}

#Preview("Low Amplitude") {
    AudioWaveformView(amplitude: 0.2, barColor: Theme.primary)
        .padding()
}

#Preview("Medium Amplitude") {
    AudioWaveformView(amplitude: 0.5, barCount: 40, barColor: Theme.secondary)
        .padding()
}

#Preview("High Amplitude") {
    AudioWaveformView(amplitude: 0.9, maxHeight: 80, barColor: Theme.error)
        .padding()
}

#Preview("Playback Context") {
    AudioWaveformView(amplitude: 0.6, barCount: 50, barColor: Theme.success, maxHeight: 40)
        .padding()
}
