import SwiftData
import SwiftUI

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Locus> { !$0.isArchived })
    private var activeLoci: [Locus]

    @Query(filter: #Predicate<Locus> { $0.isArchived })
    private var archivedLoci: [Locus]

    @Bindable var viewModel: SettingsViewModel

    @State private var showClearCacheConfirmation = false
    @State private var showDeleteArchivedConfirmation = false

    var body: some View {
        Form {
            storageSection
            archiveSection
            exportSection
        }
        .navigationTitle(String(localized: "Data Management"))
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section(String(localized: "Storage")) {
            HStack {
                Label(String(localized: "Total Loci"), systemImage: "mappin")
                Spacer()
                Text("\(activeLoci.count)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(String(localized: "Audio Files"), systemImage: "waveform")
                Spacer()
                Text("\(audioFileCount)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(String(localized: "Audio Storage"), systemImage: "internaldrive")
                Spacer()
                Text(formattedSize(viewModel.storageUsed))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(String(localized: "Database (est.)"), systemImage: "cylinder")
                Spacer()
                Text(formattedSize(estimatedDatabaseSize))
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                showClearCacheConfirmation = true
            } label: {
                Label(String(localized: "Clear Cache"), systemImage: "trash")
            }
            .confirmationDialog(
                String(localized: "Clear Cache"),
                isPresented: $showClearCacheConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Clear Cache"), role: .destructive) {
                    viewModel.clearCache(modelContext: modelContext)
                }
            } message: {
                Text(String(localized: "This will remove orphaned audio files that are no longer associated with any locus."))
            }
        }
    }

    // MARK: - Archive Section

    private var archiveSection: some View {
        Section(String(localized: "Archive")) {
            HStack {
                Label(String(localized: "Archived Loci"), systemImage: "archivebox")
                Spacer()
                Text("\(archivedLoci.count)")
                    .foregroundStyle(.secondary)
            }

            if !archivedLoci.isEmpty {
                Button(role: .destructive) {
                    showDeleteArchivedConfirmation = true
                } label: {
                    Label(String(localized: "Permanently Delete All Archived"), systemImage: "trash.fill")
                }
                .confirmationDialog(
                    String(localized: "Delete All Archived"),
                    isPresented: $showDeleteArchivedConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "Delete \(archivedLoci.count) Archived Loci"), role: .destructive) {
                        deleteAllArchived()
                    }
                } message: {
                    Text(String(localized: "This will permanently delete all archived voice notes and their audio files. This cannot be undone."))
                }
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section(String(localized: "Export")) {
            NavigationLink {
                Text(String(localized: "Export coming in a future update."))
                    .foregroundStyle(.secondary)
            } label: {
                Label(String(localized: "Export Data"), systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Helpers

    private var audioFileCount: Int {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let contents = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
        return contents?.filter { $0.pathExtension == AppConstants.Audio.fileExtension }.count ?? 0
    }

    private var estimatedDatabaseSize: Int64 {
        // Rough estimate: ~500 bytes per locus record
        Int64((activeLoci.count + archivedLoci.count) * 500)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func deleteAllArchived() {
        let fileManager = FileManager.default
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        for locus in archivedLoci {
            let audioURL = documentsURL.appendingPathComponent(locus.audioFileURL)
            try? fileManager.removeItem(at: audioURL)
            modelContext.delete(locus)
        }

        try? modelContext.save()
    }
}
