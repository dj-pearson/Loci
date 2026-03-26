import MapKit
import SwiftData
import SwiftUI
import UIKit

struct HomeMapView: View {
    @Query(filter: #Predicate<Locus> { !$0.isArchived },
           sort: \Locus.createdAt, order: .reverse)
    private var allLoci: [Locus]

    @Query private var householdMembers: [HouseholdMember]

    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: HomeMapViewModel
    let navigationRouter: NavigationRouter

    @State private var selectedLocus: Locus?
    @State private var showRecordingView = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var locusToDelete: Locus?
    @State private var showDeleteConfirmation = false
    @State private var archivedLocus: Locus?
    @State private var showUndoSnackbar = false
    @State private var locusToEdit: Locus?

    private var hasHousehold: Bool {
        !householdMembers.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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
                            withAnimation {
                                mapCameraPosition = .region(cluster.boundingRegion)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "\(cluster.loci.count) notes clustered"))
                        .accessibilityHint(String(localized: "Double tap to zoom in"))
                        .accessibilityAddTraits(.isButton)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Voice notes map"))
            .onMapCameraChange { context in
                viewModel.mapRegion = context.region
                viewModel.scheduleRegionUpdate()
            }

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
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 80)
                .padding(.horizontal, 16)
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
        .animation(.easeInOut(duration: 0.25), value: selectedLocus?.id)
        .onAppear {
            navigationRouter.consumePendingDeepLink()
            centerOnUserIfNeeded()
        }
        .sheet(isPresented: $showRecordingView) {
            // Placeholder — RecordingView will be wired here
            Text(String(localized: "Recording View"))
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

    private func centerOnUserIfNeeded() {
        viewModel.centerOnUserLocation()
        mapCameraPosition = .region(viewModel.mapRegion)
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
                        .font(.system(size: 16, weight: .semibold))
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
