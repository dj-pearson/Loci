import SwiftUI

/// Premium category pin (US-167).
///
/// Layered visual treatment:
///   * Selection halo — an animated radial gradient ring using
///     ``DesignSystem.Gradients.primaryHalo`` when selected.
///   * Glass-like stroke — subtle top highlight and bottom shadow for depth.
///   * Layered elevation via ``DesignSystem.Elevation.level2`` / ``level3``.
///   * Drop-in bounce when the pin first appears (respects Reduce Motion).
struct CategoryPinView: View {
    let category: LocusCategory
    var isShared: Bool = false
    var isSelected: Bool = false
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var haloPulse = false

    private let baseSize: CGFloat = 38
    private let borderWidth: CGFloat = 2

    private var pinSize: CGFloat {
        isSelected ? baseSize * 1.25 : baseSize
    }

    var body: some View {
        ZStack {
            // Selection halo — animated pulsing ring.
            if isSelected {
                Circle()
                    .fill(DesignSystem.Gradients.primaryHalo)
                    .frame(width: pinSize + 44, height: pinSize + 44)
                    .scaleEffect(reduceMotion ? 1.0 : (haloPulse ? 1.1 : 0.95))
                    .opacity(reduceMotion ? 0.5 : (haloPulse ? 0.3 : 0.7))
                    .animation(
                        reduceMotion
                            ? nil
                            : DesignSystem.Motion.gentle.repeatForever(autoreverses: true),
                        value: haloPulse
                    )
                    .allowsHitTesting(false)
            }

            // Category color fill with gradient highlight.
            Circle()
                .fill(category.color)
                .frame(width: pinSize, height: pinSize)
                .overlay(
                    // Glossy top highlight.
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.8),
                                    Color.white.opacity(0.25)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: borderWidth
                        )
                )
                .elevation(isSelected ? .level3 : .level2)

            Image(systemName: category.systemImageName)
                .font(.system(size: pinSize * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)

            if isShared {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(
                        Circle()
                            .fill(DesignSystem.Gradients.primary)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    )
                    .offset(x: pinSize / 2 - 4, y: -pinSize / 2 + 4)
            }
        }
        .scaleEffect(hasAppeared ? 1.0 : 0.3)
        .opacity(hasAppeared ? 1.0 : 0.0)
        .animation(
            reduceMotion ? nil : DesignSystem.Motion.bouncy,
            value: hasAppeared
        )
        .animation(reduceMotion ? nil : DesignSystem.Motion.smooth, value: isSelected)
        .onTapGesture {
            HapticManager.tabSelection()
            onTap?()
        }
        .onAppear {
            hasAppeared = true
            if isSelected { haloPulse = true }
        }
        .onChange(of: isSelected) { _, newValue in
            haloPulse = newValue
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "\(category.displayName) note\(isShared ? String(localized: ", shared") : "")"))
        .accessibilityHint(String(localized: "Double tap for details"))
    }

    func accessibilityConfigured(locationName: String?) -> some View {
        let location = locationName ?? String(localized: "Unknown location")
        return self
            .accessibilityLabel(String(localized: "\(category.displayName) note at \(location)"))
            .accessibilityHint(String(localized: "Double tap for details"))
    }
}

#Preview("All Categories") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 24) {
            ForEach(LocusCategory.allCases) { category in
                VStack(spacing: 8) {
                    CategoryPinView(category: category)
                    Text(category.displayName)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
    .background(Theme.background)
}

#Preview("Selected & Shared") {
    HStack(spacing: 28) {
        CategoryPinView(category: .food, isShared: false, isSelected: false)
        CategoryPinView(category: .food, isShared: true, isSelected: false)
        CategoryPinView(category: .food, isShared: false, isSelected: true)
        CategoryPinView(category: .food, isShared: true, isSelected: true)
    }
    .padding(40)
    .background(Theme.background)
}
