import MapKit
import SwiftData
import SwiftUI

struct HomeMapView: View {
    @Query(filter: #Predicate<Locus> { !$0.isArchived },
           sort: \Locus.createdAt, order: .reverse)
    private var allLoci: [Locus]

    @Bindable var viewModel: HomeMapViewModel
    let navigationRouter: NavigationRouter

    @State private var selectedLocus: Locus?
    @State private var showRecordingView = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapCameraPosition, selection: $selectedLocus) {
                UserAnnotation()

                let clustered = LocusClusterEngine.cluster(
                    loci: viewModel.filteredLoci(from: allLoci),
                    region: viewModel.mapRegion,
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
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange { context in
                viewModel.mapRegion = context.region
            }

            // Selected locus callout
            if let locus = selectedLocus {
                LocusCalloutView(locus: locus) {
                    navigationRouter.selectedLocusId = locus.id
                    selectedLocus = nil
                } onDismiss: {
                    selectedLocus = nil
                }
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
