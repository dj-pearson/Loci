import MapKit
import SwiftData
import SwiftUI
import UIKit

struct HomeMapView: View {
    @Query(filter: #Predicate<Locus> { !$0.isArchived },
           sort: \Locus.createdAt, order: .reverse)
    private var allLoci: [Locus]

    @Query private var householdMembers: [HouseholdMember]
    @Query private var households: [Household]

    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(NetworkMonitor.self) private var networkMonitor

    @Bindable var viewModel: HomeMapViewModel
    let navigationRouter: NavigationRouter

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedLocus: Locus?
    @State private var showRecordingView = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var locusToDelete: Locus?
    @State private var showDeleteConfirmation = false
    @State private var archivedLocus: Locus?
    @State private var showUndoSnackbar = false
    @State private var locusToEdit: Locus?
    @State private var recordViewModel: RecordViewModel?
    @State private var showMapStylePicker = false
    /// US-180: Coordinate captured by the long-press gesture. When set,
    /// the recording sheet opens pinned to this location instead of the
    /// user's current GPS position.
    @State private var pinnedCoordinate: CLLocationCoordinate2D?
    /// US-180: Drives a brief highlight pulse at the long-pressed point.
    @State private var longPressHighlight: CLLocationCoordinate2D?

    @AppStorage("loci_map_type") private var mapTypeRaw: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasHousehold: Bool {
        !householdMembers.isEmpty
    }

    private var currentHousehold: Household? {
        households.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
            Map(position: $mapCameraPosition, selection: $selectedLocus) {
                UserAnnotation()

                let clustered = viewModel.viewportAnnotations(
                    from: allLoci,
                    screenWidth: UIScreen.main.bounds.width
                )

                ForEach(clustered.singles) { locus in
                    Annotation(
                        locus.locationName ?? "",
                        coordinate: locus.coordinate
                    ) {
                        CategoryPinView(
                            category: locus.category,
                            isShared: locus.isShared,
                            isSelected: selectedLocus?.id == locus.id
                        ) {
                            selectedLocus = locus
                        }
                        .accessibilityConfigured(locationName: locus.locationName)
                    }
                    .tag(locus)
                    .annotationTitles(.hidden)
                }

                ForEach(clustered.clusters) { cluster in
                    Annotation(
                        "",
                        coordinate: cluster.coordinate
                    ) {
                        ClusterAnnotationView(
                            count: cluster.loci.count,
                            dominantCategory: cluster.dominantCategory
                        ) {
                            if reduceMotion {
                                mapCameraPosition = .region(cluster.boundingRegion)
                            } else {
                                withAnimation {
                                    mapCameraPosition = .region(cluster.boundingRegion)
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "\(cluster.loci.count) notes clustered"))
                        .accessibilityHint(String(localized: "Double tap to zoom in"))
                        .accessibilityAddTraits(.isButton)
                    }
                    .annotationTitles(.hidden)
                }

                // US-180: Highlight the long-pressed point while the
                // recording sheet is being prepared. A simple pulsing
                // ring so the user confirms they're pinning the right spot.
                if let highlight = longPressHighlight {
                    Annotation("", coordinate: highlight) {
                        ZStack {
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 3)
                                .frame(width: 44, height: 44)
                                .opacity(0.8)
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white, Color.accentColor)
                        }
                        .accessibilityHidden(true)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(currentMapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .trailing) {
                mapControlButtons
                    .padding(.trailing, 8)
                    .padding(.bottom, 100) // Clear record button
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Voice notes map"))
            .onMapCameraChange { context in
                viewModel.mapRegion = context.region
                viewModel.scheduleRegionUpdate()
            }
            // US-180: Long-press-to-pin. `.simultaneousGesture` so the Map's
            // built-in pan / zoom recognisers still receive the touch events
            // — only a 0.55s steady press triggers the pin flow.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        guard case .second(true, let drag?) = value else { return }
                        guard let coord = proxy.convert(drag.location, from: .local) else { return }
                        handleLongPress(at: coord)
                    }
            )
            } // MapReader

            // Selected locus callout
            if let locus = selectedLocus {
                LocusCalloutView(locus: locus) {
                    navigationRouter.selectedLocusId = locus.id
                    selectedLocus = nil
                } onDismiss: {
                    selectedLocus = nil
                }
                .locusContextMenu(
                    locus: locus,
                    hasHousehold: hasHousehold,
                    onViewDetails: {
                        navigationRouter.selectedLocusId = locus.id
                        selectedLocus = nil
                    },
                    onEdit: {
                        locusToEdit = locus
                        selectedLocus = nil
                    },
                    onArchive: {
                        LocusActions.archive(locus, modelContext: modelContext) { _ in
                            archivedLocus = locus
                            withAnimation {
                                showUndoSnackbar = true
                            }
                        }
                        selectedLocus = nil
                    },
                    onDelete: {
                        locusToDelete = locus
                        showDeleteConfirmation = true
                        selectedLocus = nil
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 80)
                .padding(.horizontal, 16)
            }

            // Offline indicator
            if !networkMonitor.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                    Text(String(localized: "Offline — notes saved locally"))
                        .font(.caption2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 96) // Above record button
            }

            // Record button
            Button {
                showRecordingView = true
            } label: {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .accessibilityLabel(String(localized: "Record voice note"))
            .accessibilityHint(String(localized: "Double tap to start recording"))
            .padding(.bottom, 24)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selectedLocus?.id)
        .onAppear {
            navigationRouter.consumePendingDeepLink()
            centerOnUserIfNeeded()
        }
        .sheet(isPresented: $showRecordingView, onDismiss: {
            recordViewModel = nil
            // US-180: clear the pin state once the sheet is dismissed so
            // subsequent (non-long-press) record taps return to live
            // GPS-pinning behaviour.
            pinnedCoordinate = nil
            longPressHighlight = nil
        }) {
            if let vm = recordViewModel {
                RecordingView(
                    viewModel: vm,
                    geocodingService: ReverseGeocodingService(),
                    householdName: currentHousehold?.name,
                    householdId: currentHousehold?.id,
                    pinnedCoordinate: pinnedCoordinate,
                    onDismiss: {
                        showRecordingView = false
                    }
                )
                .onAppear {
                    vm.modelContext = modelContext
                }
            }
        }
        .onChange(of: showRecordingView) { _, show in
            if show {
                recordViewModel = RecordViewModel(
                    locationService: locationService,
                    audioService: AudioService(),
                    transcriptionService: TranscriptionService()
                )
            }
        }
        .sheet(item: $locusToEdit) { locus in
            let editViewModel = LocusDetailViewModel(locus: locus)
            EditLocusSheet(viewModel: editViewModel)
                .onAppear {
                    editViewModel.modelContext = modelContext
                }
        }
        .overlay(alignment: .bottom) {
            if showUndoSnackbar, let locus = archivedLocus {
                UndoSnackbar(
                    message: String(localized: "Voice note archived"),
                    onUndo: {
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

    // MARK: - Map Style

    private var currentMapStyle: MapStyle {
        switch MKMapType(rawValue: UInt(mapTypeRaw)) ?? .standard {
        case .satellite, .satelliteFlyover:
            return .imagery
        case .hybrid, .hybridFlyover:
            return .hybrid
        default:
            return colorScheme == .dark ? .standard(elevation: .flat, emphasis: .muted) : .standard
        }
    }

    private var mapStyleIcon: String {
        switch MKMapType(rawValue: UInt(mapTypeRaw)) ?? .standard {
        case .satellite, .satelliteFlyover:
            return "globe.americas.fill"
        case .hybrid, .hybridFlyover:
            return "square.stack.3d.up.fill"
        default:
            return "map"
        }
    }

    // MARK: - Map Control Buttons

    private var mapControlButtons: some View {
        VStack(spacing: 8) {
            // Re-center on user location
            Button {
                if reduceMotion {
                    centerOnUserIfNeeded()
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        centerOnUserIfNeeded()
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.body)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(String(localized: "Center on current location"))

            // Map style toggle
            Menu {
                Button {
                    mapTypeRaw = Int(MKMapType.standard.rawValue)
                } label: {
                    Label(String(localized: "Standard"), systemImage: "map")
                }

                Button {
                    mapTypeRaw = Int(MKMapType.satellite.rawValue)
                } label: {
                    Label(String(localized: "Satellite"), systemImage: "globe.americas.fill")
                }

                Button {
                    mapTypeRaw = Int(MKMapType.hybrid.rawValue)
                } label: {
                    Label(String(localized: "Hybrid"), systemImage: "square.stack.3d.up.fill")
                }
            } label: {
                Image(systemName: mapStyleIcon)
                    .font(.body)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(String(localized: "Map style"))
        }
    }

    private func centerOnUserIfNeeded() {
        viewModel.centerOnUserLocation()
        mapCameraPosition = .region(viewModel.mapRegion)
    }

    // MARK: - US-180: Long-Press Pinning

    /// Captures the long-pressed coordinate and opens the recording sheet.
    /// The `RecordingView` then saves the locus at this coordinate instead
    /// of the user's current GPS position.
    private func handleLongPress(at coordinate: CLLocationCoordinate2D) {
        longPressHighlight = coordinate
        pinnedCoordinate = coordinate

        // Match the existing record-button code path: construct the VM if
        // we don't already have one (the .onChange(of: showRecordingView)
        // handler will cover the normal path, but we want the sheet to
        // open immediately on long-press).
        if recordViewModel == nil {
            recordViewModel = RecordViewModel(
                locationService: locationService,
                audioService: AudioService(),
                transcriptionService: TranscriptionService()
            )
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        showRecordingView = true
    }
}

// MARK: - Locus Callout

private struct LocusCalloutView: View {
    let locus: Locus
    let onNavigate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(locus.category.color)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: locus.category.systemImageName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(locus.locationName ?? String(localized: "Unknown Location"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(locus.transcription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                onNavigate()
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onNavigate()
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { _ in onDismiss() }
        )
    }
}
