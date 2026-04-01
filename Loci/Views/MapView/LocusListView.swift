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
    @State private var locusToEdit: Locus?
    @State private var paginatedQuery = PaginatedLocusQuery()
    @State private var appearedItems: Set<UUID> = []
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var pendingSearchDebounce: Task<Void, Never>?
    @State private var showUpgradeForSearch = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(NotificationService.self) private var notificationService

    private var hasHousehold: Bool {
        !householdMembers.isEmpty
    }

    /// Whether we use paginated data (time-based sorts) or all data (nearest sort).
    private var usesPagination: Bool {
        sortOrder != .nearest
    }

    /// The loci to display, filtered by category, family settings, and search text.
    /// For time-based sorts, uses paginated data. For nearest, uses all data sorted by distance.
    private var displayLoci: [Locus] {
        var loci: [Locus]
        if usesPagination {
            loci = viewModel.filteredLoci(from: paginatedQuery.loci)
        } else {
            let filtered = viewModel.filteredLoci(from: allLoci)
            guard let location = locationService.currentLocation else {
                loci = filtered
                return applySearch(to: loci)
            }
            loci = filtered.sorted {
                $0.coordinate.distance(to: location.coordinate) <
                    $1.coordinate.distance(to: location.coordinate)
            }
        }
        return applySearch(to: loci)
    }

    private func applySearch(to loci: [Locus]) -> [Locus] {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return loci }
        return loci.filter { locus in
            locus.transcription.lowercased().contains(query)
                || (locus.locationName?.lowercased().contains(query) ?? false)
                || locus.category.displayName.lowercased().contains(query)
        }
    }

    private var sections: [(title: String, loci: [Locus])] {
        guard sortOrder != .nearest else {
            return [(title: "", loci: displayLoci)]
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday)!

        var today: [Locus] = []
        var thisWeek: [Locus] = []
        var earlier: [Locus] = []

        for locus in displayLoci {
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

    @State private var showNotificationBanner = true

    var body: some View {
        List {
            if notificationService.authorizationStatus == .denied && showNotificationBanner {
                Section {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(Theme.warning)
                            .font(.body)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Proximity alerts are off"))
                                .font(.subheadline.weight(.medium))
                            Text(String(localized: "Enable notifications to be reminded when you return to a saved location."))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer(minLength: 0)

                        Button {
                            showNotificationBanner = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }

            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(Array(section.loci.enumerated()), id: \.element.id) { index, locus in
                        Button {
                            navigationRouter.selectedLocusId = locus.id
                        } label: {
                            LocusRowView(
                                locus: locus,
                                userLocation: locationService.currentLocation
                            )
                        }
                        .buttonStyle(.plain)
                        .opacity(appearedItems.contains(locus.id) || reduceMotion ? 1 : 0)
                        .offset(y: appearedItems.contains(locus.id) || reduceMotion ? 0 : 10)
                        .onAppear {
                            guard !reduceMotion, !appearedItems.contains(locus.id) else { return }
                            withAnimation(.easeOut(duration: 0.3).delay(Double(index) * 0.05)) {
                                appearedItems.insert(locus.id)
                            }
                        }
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
                        .locusContextMenu(
                            locus: locus,
                            hasHousehold: hasHousehold,
                            onViewDetails: {
                                navigationRouter.selectedLocusId = locus.id
                            },
                            onEdit: {
                                locusToEdit = locus
                            },
                            onArchive: {
                                archiveLocus(locus)
                            },
                            onDelete: {
                                locusToDelete = locus
                                showDeleteConfirmation = true
                            }
                        )
                    }
                } header: {
                    if !section.title.isEmpty {
                        Text(section.title)
                    }
                }
            }

            // Load more trigger at scroll bottom (paginated sorts only)
            if usesPagination && paginatedQuery.hasMore {
                Section {
                    HStack {
                        Spacer()
                        if paginatedQuery.isLoading {
                            ProgressView()
                        } else {
                            Text(String(localized: "Loading more..."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .onAppear {
                        paginatedQuery.loadMore(modelContext: modelContext)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            resetPagination()
        }
        .onChange(of: sortOrder) {
            resetPagination()
        }
        .onChange(of: viewModel.selectedCategories) {
            resetPagination()
        }
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
            locationService.startMonitoringSignificantLocationChanges()
            if usesPagination {
                resetPagination()
            }
        }
        .overlay {
            if displayLoci.isEmpty && !paginatedQuery.isLoading {
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
        .sheet(item: $locusToEdit) { locus in
            let editViewModel = LocusDetailViewModel(locus: locus)
            EditLocusSheet(viewModel: editViewModel)
                .onAppear {
                    editViewModel.modelContext = modelContext
                }
        }
        .searchable(
            text: $searchText,
            prompt: String(localized: "Search voice notes...")
        )
        .onChange(of: searchText) { _, newValue in
            pendingSearchDebounce?.cancel()
            pendingSearchDebounce = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                debouncedSearchText = InputSanitizer.sanitizeSearchQuery(newValue)
            }
        }
        .overlay {
            if !debouncedSearchText.isEmpty && displayLoci.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Results"),
                    systemImage: "magnifyingglass",
                    description: Text(String(localized: "No voice notes match \"\(debouncedSearchText)\""))
                )
            }
        }
        .refreshable {
            resetPagination()
        }
    }

    // MARK: - Pagination

    private func resetPagination() {
        guard usesPagination else { return }
        paginatedQuery.reset(
            sortOrder: sortOrder == .oldest ? .forward : .reverse,
            modelContext: modelContext
        )
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(locus.transcription.isEmpty
                     ? String(localized: "Voice Note")
                     : locus.transcription)
                    .font(.subheadline)
                    .lineLimit(2)

                if locus.isShared, let creatorName = locus.createdByName {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text(String(localized: "Shared by \(creatorName)"))
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.primary)
                }

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
