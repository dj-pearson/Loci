import SwiftUI
import UIKit

struct LocusContextMenu: ViewModifier {
    let locus: Locus
    let hasHousehold: Bool
    let onViewDetails: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                onViewDetails()
            } label: {
                Label(String(localized: "View Details"), systemImage: "eye")
            }

            Button {
                onEdit()
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }

            Button {
                UIPasteboard.general.string = locus.transcription
            } label: {
                Label(String(localized: "Copy Transcription"), systemImage: "doc.on.doc")
            }
            .disabled(locus.transcription.isEmpty)

            if hasHousehold {
                Button {
                    locus.isShared.toggle()
                    locus.updatedAt = Date()
                } label: {
                    Label(
                        locus.isShared
                            ? String(localized: "Unshare with Family")
                            : String(localized: "Share with Family"),
                        systemImage: locus.isShared ? "person.2.slash" : "person.2"
                    )
                }
            }

            Divider()

            Button(role: .destructive) {
                onArchive()
            } label: {
                Label(String(localized: "Archive"), systemImage: "archivebox")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }
}

extension View {
    func locusContextMenu(
        locus: Locus,
        hasHousehold: Bool,
        onViewDetails: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onArchive: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(LocusContextMenu(
            locus: locus,
            hasHousehold: hasHousehold,
            onViewDetails: onViewDetails,
            onEdit: onEdit,
            onArchive: onArchive,
            onDelete: onDelete
        ))
    }
}
