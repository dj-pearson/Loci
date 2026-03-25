import MapKit
import SwiftUI

struct LocusDetailView: View {
    @Bindable var viewModel: LocusDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false

    private var locus: Locus { viewModel.locus }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Category badge and date
                headerSection

                // Location info
                locationSection

                // Transcription
                transcriptionSection

                // Map snippet
                mapSnippet

                // Shared info
                if locus.isShared {
                    sharedSection
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle(locus.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }

                Button {
                    if locus.isArchived {
                        viewModel.unarchiveLocus()
                    } else {
                        viewModel.archiveLocus()
                        dismiss()
                    }
                } label: {
                    Image(systemName: locus.isArchived ? "tray.and.arrow.up" : "archivebox")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            // EditLocusSheet placeholder — will be implemented in US-040
            Text(String(localized: "Edit Locus"))
        }
        .confirmationDialog(
            String(localized: "Delete Voice Note"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                viewModel.deleteLocus()
                dismiss()
            }
        } message: {
            Text(String(localized: "This will permanently delete the voice note and its audio recording."))
        }
        .alert(
            String(localized: "Error"),
            isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.clearError() }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: locus.category.systemImageName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(locus.category.color, in: Circle())

                Text(locus.category.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(locus.category.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(locus.category.color.opacity(0.1), in: Capsule())

            Spacer()

            Text(locus.createdAt, style: .relative)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = locus.locationName {
                Text(name)
                    .font(Theme.Typography.headline)
            }

            Text(String(localized: "\(locus.latitude, specifier: "%.4f"), \(locus.longitude, specifier: "%.4f")"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Transcription"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            Text(locus.transcription.isEmpty
                 ? String(localized: "No transcription available")
                 : locus.transcription)
                .font(Theme.Typography.body)
                .foregroundStyle(locus.transcription.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
    }

    // MARK: - Map Snippet

    private var mapSnippet: some View {
        Map(initialPosition: .region(
            MKCoordinateRegion(
                center: locus.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        )) {
            Annotation("", coordinate: locus.coordinate) {
                CategoryPinView(category: locus.category)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .allowsHitTesting(false)
    }

    // MARK: - Shared

    private var sharedSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.caption)
                .foregroundStyle(Theme.primary)

            if let name = locus.createdByName {
                Text(String(localized: "Shared by \(name)"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(String(localized: "Shared with family"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }
}
