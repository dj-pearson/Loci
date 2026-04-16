import SwiftUI

enum Theme {
    // MARK: - Colors

    /// Primary brand color — used for key actions, active elements, and accents.
    static let primary = Color(.systemBlue)

    /// Secondary accent — used for supporting UI elements and badges.
    static let secondary = Color(.systemIndigo)

    /// App background — adapts to light/dark mode.
    static let background = Color(.systemBackground)

    /// Elevated surface (cards, sheets) — adapts to light/dark mode.
    static let surface = Color(.secondarySystemBackground)

    /// Primary text — high contrast against background.
    static let textPrimary = Color(.label)

    /// Secondary text — lower emphasis, captions, metadata.
    static let textSecondary = Color(.secondaryLabel)

    /// Error / destructive — used for alerts and delete actions.
    static let error = Color(.systemRed)

    /// Success — used for confirmations and completion states.
    static let success = Color(.systemGreen)

    /// Warning — used for caution states and non-critical alerts.
    static let warning = Color(.systemOrange)

    // MARK: - Typography

    enum Typography {
        static let largeTitle: Font = .largeTitle
        static let title: Font = .title2
        static let headline: Font = .headline
        static let body: Font = .body
        static let caption: Font = .caption
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }
}
