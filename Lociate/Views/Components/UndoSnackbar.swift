import SwiftData
import SwiftUI
import UIKit

struct UndoSnackbar: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "archivebox")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation {
                        isVisible = false
                    }
                    onUndo()
                } label: {
                    Text(String(localized: "Undo"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 12)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .padding(.horizontal, Theme.Spacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    guard isVisible else { return }
                    withAnimation {
                        isVisible = false
                    }
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Archive/Delete Action Helpers

enum LocusActions {
    static func archive(
        _ locus: Locus,
        modelContext: ModelContext?,
        onComplete: @escaping (_ undo: @escaping () -> Void) -> Void
    ) {
        locus.isArchived = true
        locus.updatedAt = Date()
        try? modelContext?.save()
        NotificationCenter.default.post(name: .locusDidCreate, object: nil)

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        onComplete {
            locus.isArchived = false
            locus.updatedAt = Date()
            try? modelContext?.save()
            NotificationCenter.default.post(name: .locusDidCreate, object: nil)
        }
    }

    static func delete(
        _ locus: Locus,
        modelContext: ModelContext?
    ) {
        // Delete audio file
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
        if let audioURL = documentsDirectory?.appendingPathComponent(locus.audioFileURL) {
            try? FileManager.default.removeItem(at: audioURL)
        }

        modelContext?.delete(locus)
        try? modelContext?.save()
        NotificationCenter.default.post(name: .locusDidCreate, object: nil)

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

#Preview {
    VStack {
        Spacer()
        UndoSnackbar(
            message: "Voice note archived",
            onUndo: {},
            onDismiss: {}
        )
    }
}
