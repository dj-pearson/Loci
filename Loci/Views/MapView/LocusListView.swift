import CoreLocation
import SwiftData
import SwiftUI
import UIKit

enum LocusSortOrder: String, CaseIterable, Identifiable {
    case nearest
    case newest
    case oldest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nearest: String(localized: "Nearest")
        case .newest: String(localized: "Newest")
        case .oldest: String(localized: "Oldest")
        }
    }
}

struct LocusListView: View {
    @Query(filter: #Predicate<Locus> { !$0.isArchived },
           sort: \Locus.createdAt, order: .reverse)
    private var allLoci: [Locus]

    @Query private var householdMembers: [HouseholdMember]

    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: HomeMapViewModel
    let locationService: LocationService
    let navigationRouter: NavigationRouter

    @State private var sortOrder: LocusSortOrder = .newest
    @State private var locusToDelete: Locus?
    @State private var showDeleteConfirmation = false
    @State private var archivedLocus: Locus?
    @State private var showUndoSnackbar = false

    private var hasHousehold: Bool {
        !householdMembers.isEmpty
    }

    private var sortedLoci: [Locus] {
        let filtered = viewModel.filteredLoci(from: allLoci)
        switch sortOrder {
        case .nearest:
            guard let location = locationService.currentLocation else {
                return filtered
            }
            return filtered.sorted {
                $0.coordinate.distance(to: location.coordinate) <
                    $1.coordinate.distance(to: location.coordinate)
            }
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var sections: [(title: String, loci: [Locus])] {
        guard sortOrder != .nearest else {
            return [(title: "", loci: sortedLoci)]
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday)!

        var today: [Locus] = []
        var thisWeek: [Locus] = []
        var earlier: [Locus] = []

        for locus in sortedLoci {
            if locus.createdAt >= startOfToday {
                today.append(locus)
            } else if locus.createdAt >= startOfWeek {
                thisWeek.append(locus)
            } else {
                earlier.append(locus)
            }
        }

        var result: [(String, [Locus])] = []
        if !today.isEmpty { result.append((String(localized: "Today"), today)) }
        if !thisWeek.isEmpty { result.append((String(localized: "This Week"), thisWeek)) }
        if !earlier.isEmpty { result.append((String(localized: "Earlier"), earlier)) }
        return result
    }

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.loci) { locus in
                        Button {
                            navigationRouter.selectedLocusId = locus.id
                        } label: {
                            LocusRowView(
                                locus: locus,
                                userLocation: locationService.currentLocation
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                locusToDelete = locus
                                showDeleteConfirmation = true
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }

                            Button {
                                archiveLocus(locus)
                            } label: {
                                Label(String(localized: "Archive"), systemImage: "archivebox")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if hasHousehold {
                                Button {
                                    toggleSharing(locus)
                                } label: {
                                    Label(
                                        locus.isShared
                                            ? String(localized: "Unshare")
                                            : String(localized: "Share"),
                                        systemImage: "person.2"
                                    )
                                }
                                .tint(.green)
                            }
                        }
                    }
                } header: {
                    if !section.title.isEmpty {
                        Text(section.title)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker(String(localized: "Sort"), selection: $sortOrder) {
                    ForEach(LocusSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .refreshable {
            // Trigger a location update to re-sort by proximity
            locationService.startMonitoringSignificantLocationChanges()
        }
        .overlay {
            if sortedLoci.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Loci"),
                    systemImage: "mappin.slash",
                    description: Text(String(localized: "Record a voice note to pin it here."))
                )
            }
        }
        .overlay(alignment: .bottom) {
            if showUndoSnackbar, let locus = archivedLocus {
                UndoSnackbar(
                    message: String(localized: "Voice note archived"),
                    onUndo: {
                        undoArchive(locus)
                    },
                    onDismiss: {
                        showUndoSnackbar = false
                        archivedLocus = nil
                    }
                )
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .alert(
            String(localized: "Delete Voice Note"),
            isPresented: $showDeleteConfirmation,
            presenting: locusToDelete
        ) { locus in
            Button(String(localized: "Delete"), role: .destructive) {
                LocusActions.delete(locus, modelContext: modelContext)
                locusToDelete = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                locusToDelete = nil
            }
        } message: { _ in
            Text(String(localized: "This will permanently delete the voice note and its audio recording."))
        }
    }

    // MARK: - Actions

    private func archiveLocus(_ locus: Locus) {
        LocusActions.archive(locus, modelContext: modelContext) { undo in
            archivedLocus = locus
            withAnimation {
                showUndoSnackbar = true
            }
        }
    }

    private func undoArchive(_ locus: Locus) {
        locus.isArchived = false
        locus.updatedAt = Date()
        try? modelContext.save()
        NotificationCenter.default.post(name: .locusDidCreate, object: nil)

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation {
            showUndoSnackbar = false
            archivedLocus = nil
        }
    }

    private func toggleSharing(_ locus: Locus) {
        locus.isShared.toggle()
        locus.updatedAt = Date()
        try? modelContext.save()

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - Locus Row

struct LocusRowView: View {
    let locus: Locus
    let userLocation: CLLocation?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(locus.category.color)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: locus.category.systemImageName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(locus.transcription.isEmpty
                     ? String(localized: "Voice Note")
                     : locus.transcription)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let name = locus.locationName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(locus.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let userLocation {
                let distance = locus.coordinate.distance(to: userLocation.coordinate)
                Text(formatDistance(distance))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
}
