import SwiftUI

struct EditLocusSheet: View {
    @Bindable var viewModel: LocusDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedTranscription: String
    @State private var selectedCategory: LocusCategory
    @State private var showReRecordConfirmation = false

    init(viewModel: LocusDetailViewModel) {
        self.viewModel = viewModel
        _editedTranscription = State(initialValue: viewModel.locus.transcription)
        _selectedCategory = State(initialValue: viewModel.locus.category)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Category picker
                    categorySection

                    // Transcription editor
                    transcriptionSection

                    // Re-record option
                    reRecordSection
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle(String(localized: "Edit Voice Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
        }
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(String(localized: "Category"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LocusCategory.allCases) { category in
                        let isSelected = selectedCategory == category

                        Button {
                            selectedCategory = category
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: category.systemImageName)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(category.displayName)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? category.color : Theme.surface)
                            )
                            .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(String(localized: "Transcription"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            TextEditor(text: $editedTranscription)
                .font(Theme.Typography.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Re-record Section

    private var reRecordSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                showReRecordConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "mic.badge.plus")
                    Text(String(localized: "Re-record Audio"))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
            .confirmationDialog(
                String(localized: "Re-record Audio"),
                isPresented: $showReRecordConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Replace Recording"), role: .destructive) {
                    // Re-record will be wired to RecordViewModel when available
                    dismiss()
                }
            } message: {
                Text(String(localized: "This will replace the current audio recording. This cannot be undone."))
            }

            Text(String(localized: "Replaces the existing recording and transcription."))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Save

    private var hasChanges: Bool {
        editedTranscription != viewModel.locus.transcription
            || selectedCategory != viewModel.locus.category
    }

    private func save() {
        if selectedCategory != viewModel.locus.category {
            viewModel.updateCategory(selectedCategory)
        }
        if editedTranscription != viewModel.locus.transcription {
            viewModel.updateTranscription(editedTranscription)
        }
        dismiss()
    }
}
