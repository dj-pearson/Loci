import CoreLocation
import SwiftUI

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: RecordViewModel
    let geocodingService: ReverseGeocodingService
    var householdName: String?
    var householdId: UUID?
    var createdByName: String?
    /// US-180: When non-nil, the saved Locus is pinned at this coordinate
    /// instead of the device's current location. Used by the map's
    /// long-press-to-pin gesture to capture a memory about a place that
    /// isn't where the user is physically standing.
    var pinnedCoordinate: CLLocationCoordinate2D?
    var onDismiss: (() -> Void)?

    @State private var locationName: String?
    @State private var detectedCategory: LocusCategory = .general
    @State private var showPostRecordingSheet = false
    @State private var recordingResult: (url: URL, transcription: String, coordinate: CLLocationCoordinate2D)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background gradient based on detected category
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                // Location name at top
                locationHeader

                Spacer()

                // Transcription area
                transcriptionArea

                Spacer()

                // Record button centered
                RecordButton(
                    isRecording: viewModel.isRecording,
                    amplitude: viewModel.amplitude
                ) {
                    Task {
                        if viewModel.isRecording {
                            if let result = await viewModel.stopRecording() {
                                recordingResult = result
                                detectedCategory = AICategoryService.categorize(transcription: result.transcription)
                                showPostRecordingSheet = true
                            }
                        } else {
                            await viewModel.startRecording()
                        }
                    }
                }

                // Duration timer below button
                durationLabel

                Spacer()
                    .frame(height: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .task(id: locationTaskID) {
            await updateLocationName()
        }
        .overlay {
            if viewModel.isPreparing {
                preparingOverlay
            }
        }
        .alert(
            String(localized: "Recording Error"),
            isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button(String(localized: "OK")) {
                viewModel.clearError()
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .sheet(isPresented: $showPostRecordingSheet) {
            if let result = recordingResult {
                PostRecordingSheet(
                    audioURL: result.url,
                    transcription: result.transcription,
                    coordinate: result.coordinate,
                    locationName: locationName,
                    detectedCategory: detectedCategory,
                    householdName: householdName,
                    onSave: { category, shared in
                        showPostRecordingSheet = false
                        viewModel.modelContext = modelContext
                        // US-180: Prefer the long-pressed pinned coordinate
                        // over the device's current location when it was set
                        // by the map gesture.
                        let saveCoordinate = pinnedCoordinate ?? result.coordinate
                        Task {
                            await viewModel.saveLocus(
                                audioURL: result.url,
                                transcription: result.transcription,
                                coordinate: saveCoordinate,
                                category: category,
                                isShared: shared,
                                householdId: shared ? householdId : nil,
                                createdByName: shared ? createdByName : nil
                            )
                        }
                    },
                    onDiscard: {
                        showPostRecordingSheet = false
                        onDismiss?()
                    }
                )
                .interactiveDismissDisabled()
                .presentationDetents([.medium, .large])
            }
        }
        .onChange(of: viewModel.didSaveLocus) { _, saved in
            if saved {
                onDismiss?()
            }
        }
        .onChange(of: viewModel.didReachMaxDuration) { _, reached in
            if reached {
                Task {
                    if let result = await viewModel.stopRecording() {
                        recordingResult = result
                        detectedCategory = AICategoryService.categorize(transcription: result.transcription)
                        showPostRecordingSheet = true
                    }
                }
            }
        }
    }

    // MARK: - Location Header

    private var locationHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // US-180: Different icon when we're pinning at a non-current
            // location so the user sees they're recording about a place
            // they long-pressed, not about where they are right now.
            Image(systemName: pinnedCoordinate != nil ? "mappin.circle.fill" : "location.fill")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            if pinnedCoordinate != nil {
                Text(String(localized: "Pinned at"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let name = locationName {
                Text(name)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            } else {
                Text(String(localized: "Locating..."))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(locationName.map { String(localized: "Location: \($0)") }
            ?? String(localized: "Determining location"))
    }

    // MARK: - Transcription Area

    private var transcriptionArea: some View {
        Group {
            if viewModel.isRecording && !viewModel.transcription.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(viewModel.transcription)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.md)
                            .id("transcriptionEnd")
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: viewModel.transcription) {
                        if reduceMotion {
                            proxy.scrollTo("transcriptionEnd", anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("transcriptionEnd", anchor: .bottom)
                            }
                        }
                    }
                }
                .transition(.opacity)
            } else if !viewModel.isRecording {
                Text(String(localized: "Tap to record a voice note"))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else {
                // Recording but no transcription yet
                Text(String(localized: "Listening..."))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isRecording)
        .animation(.easeInOut(duration: 0.3), value: viewModel.transcription.isEmpty)
    }

    // MARK: - Duration Label

    private var durationLabel: some View {
        Group {
            if viewModel.isRecording {
                Text(formattedDuration)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                    .accessibilityLabel(String(localized: "Recording duration: \(formattedDuration)"))
            } else {
                // Reserve space so layout doesn't jump
                Text(" ")
                    .font(.system(.title3, design: .monospaced))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isRecording)
    }

    // MARK: - Background Gradient

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                detectedCategory.color.opacity(0.08),
                Theme.background,
                Theme.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: detectedCategory)
    }

    // MARK: - Preparing Overlay

    private var preparingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            ProgressView(String(localized: "Preparing..."))
                .padding(Theme.Spacing.lg)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
    }

    // MARK: - Helpers

    /// US-180: Drives the geocode task. When we have a pinned coordinate
    /// from the map's long-press we lock to that; otherwise we react to
    /// currentLocation updates as they arrive.
    private var locationTaskID: String {
        if let pinnedCoordinate {
            return "pinned:\(pinnedCoordinate.latitude),\(pinnedCoordinate.longitude)"
        }
        if let coord = viewModel.currentLocation?.coordinate {
            return "live:\(coord.latitude)"
        }
        return "none"
    }

    private var formattedDuration: String {
        let totalSeconds = Int(viewModel.recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func updateLocationName() async {
        // US-180: If a pinned coordinate was provided by the map's
        // long-press gesture, resolve the name for that coordinate — not
        // for where the user is physically standing.
        let coordinate: CLLocationCoordinate2D
        if let pinnedCoordinate {
            coordinate = pinnedCoordinate
        } else if let location = viewModel.currentLocation {
            coordinate = location.coordinate
        } else {
            return
        }
        let name = try? await geocodingService.reverseGeocode(coordinate)
        locationName = name
    }
}

#Preview {
    RecordingView(
        viewModel: RecordViewModel(
            locationService: LocationService(),
            audioService: AudioService(),
            transcriptionService: TranscriptionService()
        ),
        geocodingService: ReverseGeocodingService()
    )
}
