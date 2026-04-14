import SwiftUI

/// Premium design tokens that layer on top of ``Theme`` to give Lociate a
/// cohesive, high-end visual language across the app. ``Theme`` remains the
/// single source of truth for base semantic colors; ``DesignSystem`` adds the
/// motion, elevation, gradient, and spacing primitives needed for a premium
/// feel without duplicating those semantics.
enum DesignSystem {

    // MARK: - Extended Spacing Scale

    /// Finer-grained spacing tokens aligned to an 8pt grid (with 2pt/4pt
    /// half-steps for tight compositions like chips and inline icons).
    enum Space {
        /// 2pt — hairline separation (icon ↔ label).
        static let hairline: CGFloat = 2
        /// 4pt — micro (chip padding, dense list).
        static let xxs: CGFloat = 4
        /// 8pt — small (tight groups).
        static let xs: CGFloat = 8
        /// 12pt — compact (form fields, card inner).
        static let sm: CGFloat = 12
        /// 16pt — default gutter.
        static let md: CGFloat = 16
        /// 20pt — section inner.
        static let lg: CGFloat = 20
        /// 24pt — section outer.
        static let xl: CGFloat = 24
        /// 32pt — hero padding.
        static let xxl: CGFloat = 32
        /// 48pt — full hero block.
        static let xxxl: CGFloat = 48
    }

    // MARK: - Radius Scale

    /// Corner radius scale designed for nested surfaces (outer > inner).
    enum Radius {
        /// 6pt — pills, small chips.
        static let pill: CGFloat = 6
        /// 10pt — inner content (inside a card).
        static let sm: CGFloat = 10
        /// 14pt — card default.
        static let md: CGFloat = 14
        /// 20pt — hero card / sheet top.
        static let lg: CGFloat = 20
        /// 28pt — floating hero surface.
        static let xl: CGFloat = 28
        /// 999pt — fully rounded (circles, FABs).
        static let full: CGFloat = 999
    }

    // MARK: - Elevation

    /// Layered shadow tokens. Each elevation is rendered as a soft ambient
    /// shadow; callers can stack an additional key shadow for extra depth.
    struct Elevation {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        let opacity: Double

        /// Resting surface — subtle separation from background.
        static let level1 = Elevation(
            color: .black, radius: 6, x: 0, y: 2, opacity: 0.06
        )

        /// Cards, list items.
        static let level2 = Elevation(
            color: .black, radius: 12, x: 0, y: 4, opacity: 0.08
        )

        /// Floating action buttons, sheets.
        static let level3 = Elevation(
            color: .black, radius: 20, x: 0, y: 8, opacity: 0.12
        )

        /// Hero elements, modal surfaces.
        static let level4 = Elevation(
            color: .black, radius: 32, x: 0, y: 14, opacity: 0.18
        )
    }

    // MARK: - Gradients

    /// Brand gradients used for premium hero surfaces, paywall cards, and
    /// the record button. All gradients use the semantic ``Theme`` colors so
    /// they adapt to light/dark mode automatically.
    enum Gradients {
        /// Primary diagonal — top-leading to bottom-trailing.
        static let primary = LinearGradient(
            colors: [Theme.primary, Theme.secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Soft primary radial — used for hero halos behind key elements.
        static let primaryHalo = RadialGradient(
            colors: [Theme.primary.opacity(0.35), Theme.primary.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: 220
        )

        /// Record active — warm red/orange for the recording hero state.
        static let record = LinearGradient(
            colors: [Theme.error, Theme.warning],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Premium tier showcase — indigo → blue → teal.
        static let premium = LinearGradient(
            colors: [
                Color(.systemIndigo),
                Color(.systemBlue),
                Color(.systemTeal)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Family tier showcase — warm gold for paywall.
        static let family = LinearGradient(
            colors: [
                Color(.systemOrange),
                Color(.systemPink)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Glass surface tint — layered over a material for subtle color.
        static let glassTint = LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Motion

    /// Spring presets used across premium transitions so motion feels
    /// consistent. Prefer these over ad-hoc ``.spring(...)`` calls.
    enum Motion {
        /// Snappy — small controls (buttons, chips, toggles).
        static let snappy: Animation = .spring(response: 0.28, dampingFraction: 0.72)
        /// Smooth — card reveals, sheet presentation.
        static let smooth: Animation = .spring(response: 0.42, dampingFraction: 0.82)
        /// Gentle — hero transitions, onboarding pages.
        static let gentle: Animation = .spring(response: 0.55, dampingFraction: 0.88)
        /// Bouncy — celebratory feedback (save success, unlock).
        static let bouncy: Animation = .spring(response: 0.38, dampingFraction: 0.62)
        /// Linear ease-out for value-driven animations like amplitude rings.
        static let amplitude: Animation = .easeOut(duration: 0.08)

        /// Standard stagger delay between sibling elements in a list reveal.
        static let stagger: Double = 0.04
    }

    // MARK: - Durations

    /// Opinionated motion durations (seconds) for non-spring animations.
    enum Duration {
        static let instant: Double = 0.12
        static let short: Double = 0.22
        static let medium: Double = 0.34
        static let long: Double = 0.55
        static let hero: Double = 0.8
    }

    // MARK: - Surfaces

    /// Material presets used for premium glass-style surfaces.
    enum Surface {
        /// Thin translucent surface (e.g. floating toolbars).
        static let glassThin: Material = .ultraThinMaterial
        /// Regular translucent surface (sheets, cards over imagery).
        static let glass: Material = .regularMaterial
        /// Thick translucent surface (modal backgrounds).
        static let glassThick: Material = .thickMaterial
    }
}

// MARK: - Elevation modifier

extension View {
    /// Applies a layered shadow from the ``DesignSystem.Elevation`` token.
    func elevation(_ level: DesignSystem.Elevation) -> some View {
        self.shadow(
            color: level.color.opacity(level.opacity),
            radius: level.radius,
            x: level.x,
            y: level.y
        )
    }

    /// Premium card container — rounded surface with elevation and optional
    /// glass background. Use for list cards, paywall tiers, and hero tiles.
    func premiumCard(
        radius: CGFloat = DesignSystem.Radius.md,
        elevation: DesignSystem.Elevation = .level2,
        glass: Bool = false
    ) -> some View {
        self
            .background(
                Group {
                    if glass {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(DesignSystem.Surface.glass)
                            .overlay(
                                RoundedRectangle(cornerRadius: radius, style: .continuous)
                                    .fill(DesignSystem.Gradients.glassTint)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.surface)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .elevation(elevation)
    }
}
