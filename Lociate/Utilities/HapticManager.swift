import UIKit

enum HapticManager {
    // MARK: - Recording

    static func recordStart() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    static func recordStop() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Actions

    static func saveSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    static func archive() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    static func delete() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }

    // MARK: - Navigation

    static func tabSelection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: - Premium Sequences (US-169)

    /// Two-beat confirmation when a recording starts: medium impact followed
    /// by a light impact 90ms later. Creates a "lock-in" feel that makes the
    /// start of a recording feel intentional and premium.
    static func recordStartSequence() {
        let primary = UIImpactFeedbackGenerator(style: .medium)
        primary.prepare()
        primary.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            let secondary = UIImpactFeedbackGenerator(style: .light)
            secondary.prepare()
            secondary.impactOccurred()
        }
    }

    /// Light impact followed by a success notification — used when a locus
    /// is saved. The light tap primes the user before the success chime.
    static func saveSuccessSequence() {
        let tap = UIImpactFeedbackGenerator(style: .light)
        tap.prepare()
        tap.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let success = UINotificationFeedbackGenerator()
            success.prepare()
            success.notificationOccurred(.success)
        }
    }

    /// Selection → heavy impact → success — used when a paid tier is
    /// unlocked or a household invite is accepted. Feels celebratory.
    static func unlockSequence() {
        let selection = UISelectionFeedbackGenerator()
        selection.prepare()
        selection.selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.prepare()
            impact.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            let success = UINotificationFeedbackGenerator()
            success.prepare()
            success.notificationOccurred(.success)
        }
    }
}
