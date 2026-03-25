import CoreLocation
import SwiftUI

struct PostRecordingSheet: View {
    let audioURL: URL
    let transcription: String
    let coordinate: CLLocationCoordinate2D
    let locationName: String?
    let detectedCategory: LocusCategory
    let hasHousehold: Bool
    let onSave: (LocusCategory, Bool) -> Void
    let onDiscard: () -> Void

    @State private var selectedCategory: LocusCategory
    @State private var shareWithFamily = false

    @State private var playerService = AudioPlayerService()

    init(
        audioURL: URL,
        transcription: String,
        coordinate: CLLocationCoordinate2D,
        locationName: String?,
        detectedCategory: LocusCategory,
        hasHousehold: Bool,
        onSave: @escaping (LocusCategory, Bool) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.audioURL = audioURL
        self.transcription = transcription
        self.coordinate = coordinate
        self.locationName = locationName
        self.detectedCategory = detectedCategory
        self.hasHousehold = hasHousehold
        self.onSave = onSave
        self.onDiscard = onDiscard
        _selectedCategory = State(initialValue: detectedCategory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Location
                    locationSection

                    // Transcription preview
                    transcriptionSection

                    // Audio playback
                    playbackButton

                    // Category picker
                    categorySection

                    // Share with family toggle
                    if hasHousehold {
                        familyToggle
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.background)
            .navigationTitle(String(localized: "New Voice Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Discard")) {
                        playerService.stop()
                        onDiscard()
                    }
                    .foregroundStyle(Theme.error)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        playerService.stop()
                        onSave(selectedCategory, shareWithFamily)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onDisappear {
            playerService.stop()
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(selectedCategory.color)

            Text(locationName ?? String(localized: "Unknown Location"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Location: \(locationName ?? String(localized: "Unknown"))"))
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(String(localized: "Transcription"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            Text(transcription.isEmpty ? String(localized: "No transcription available") : transcription)
                .font(Theme.Typography.body)
                .foregroundStyle(transcription.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
    }

    // MARK: - Playback Button

    private var playbackButton: some View {
        Button {
            if playerService.isPlaying {
                playerService.pause()
            } else {
                playerService.play(url: audioURL)
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: playerService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)

                if playerService.isPlaying {
                    Text(String(localized: "Pause Preview"))
                        .font(Theme.Typography.body)
                } else {
                    Text(String(localized: "Play Preview"))
                        .font(Theme.Typography.body)
                }

                Spacer()

                if playerService.duration > 0 {
                    Text(formattedTime(playerService.currentTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    Text("/")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(formattedTime(playerService.duration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playerService.isPlaying
            ? String(localized: "Pause audio preview")
            : String(localized: "Play audio preview"))
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(String(localized: "Category"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(LocusCategory.allCases) { category in
                        CategoryPill(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Family Toggle

    private var familyToggle: some View {
        Toggle(isOn: $shareWithFamily) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Theme.secondary)
                Text(String(localized: "Share with Family"))
                    .font(Theme.Typography.body)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .accessibilityLabel(String(localized: "Share this voice note with your family"))
    }

    // MARK: - Helpers

    private func formattedTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Category Pill

private struct CategoryPill: View {
    let category: LocusCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: category.systemImageName)
                    .font(.caption)
                Text(category.displayName)
                    .font(Theme.Typography.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                isSelected ? category.color.opacity(0.15) : Color.clear,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? category.color : Theme.textSecondary.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? category.color : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    PostRecordingSheet(
        audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
        transcription: "Remember to check out that new Italian restaurant on Main Street. The pasta was amazing last time.",
        coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        locationName: "123 Main St, San Francisco",
        detectedCategory: .food,
        hasHousehold: true,
        onSave: { _, _ in },
        onDiscard: {}
    )
}
