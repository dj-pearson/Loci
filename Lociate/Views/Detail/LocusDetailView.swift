import MapKit
import SwiftUI
import UIKit

struct LocusDetailView: View {
    @Bindable var viewModel: LocusDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    // US-182: Share sheet state.
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var isPreparingShare = false
    @State private var shareDecryptedAudioURL: URL?

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

                // Audio playback
                AudioPlaybackBar(
                    playerService: viewModel.playerService,
                    audioURL: viewModel.audioURL,
                    waveformColor: locus.category.color
                )

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
                // US-182: Share transcription, location, and audio outside
                // of family sharing (Messages, Mail, Notes, AirDrop, etc.).
                Button {
                    Task { await prepareAndShowShareSheet() }
                } label: {
                    if isPreparingShare {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .accessibilityLabel(String(localized: "Share voice note"))
                .disabled(isPreparingShare)

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
        .sheet(isPresented: $showShareSheet, onDismiss: {
            // US-182: Release the decrypted audio temp file so plaintext
            // audio doesn't linger in /tmp after sharing.
            if let url = shareDecryptedAudioURL {
                AudioEncryptionService.releaseTempFile(at: url)
                shareDecryptedAudioURL = nil
            }
            shareItems = []
        }, content: {
            LocusShareSheet(items: shareItems)
        })
        .sheet(isPresented: $showEditSheet) {
            EditLocusSheet(viewModel: viewModel)
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 28, minHeight: 28)
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

    // MARK: - US-182: Share

    /// Builds the share payload (transcription, Apple Maps link, audio file)
    /// and presents UIActivityViewController. Audio is decrypted into a
    /// tracked temp file that is released when the share sheet dismisses.
    private func prepareAndShowShareSheet() async {
        isPreparingShare = true
        defer { isPreparingShare = false }

        var items: [Any] = []

        let transcript = locus.transcription
        if !transcript.isEmpty {
            items.append(transcript)
        }

        let coord = locus.coordinate
        let place = locus.locationName.map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }
            ?? ""
        let mapsURLString = "https://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)&q=\(place)"
        if let mapsURL = URL(string: mapsURLString) {
            items.append(mapsURL)
        }

        if let audioURL = viewModel.audioURL,
           FileManager.default.fileExists(atPath: audioURL.path) {
            if AudioEncryptionService.isFileEncrypted(at: audioURL) {
                if let decrypted = try? AudioEncryptionService.decryptFileForPlayback(at: audioURL) {
                    shareDecryptedAudioURL = decrypted
                    items.append(decrypted)
                }
            } else {
                items.append(audioURL)
            }
        }

        shareItems = items
        showShareSheet = true
    }
}

// MARK: - US-182: Share Sheet Wrapper

private struct LocusShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
