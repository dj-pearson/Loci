import AVFoundation
import CoreLocation
import Foundation
import SwiftData
import UIKit
import WidgetKit

@Observable
final class RecordViewModel {
    // MARK: - State

    private(set) var isRecording = false
    private(set) var isPreparing = false
    private(set) var isSaving = false
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var errorMessage: String?
    private(set) var didSaveLocus = false
    private(set) var didReachMaxDuration = false

    var transcription: String {
        transcriptionService.transcription
    }

    var amplitude: Float {
        audioService.currentAmplitude
    }

    var currentLocation: CLLocation? {
        locationService.currentLocation
    }

    /// Set when a premium feature is blocked; drives the upgrade prompt.
    private(set) var blockedFeature: BlockedFeature?

    // MARK: - Dependencies

    private let locationService: LocationService
    private let audioService: AudioService
    private let transcriptionService: TranscriptionService
    private let geocodingService: ReverseGeocodingService
    private let geofenceManager: GeofenceManager
    private let subscriptionService: SubscriptionService

    // MARK: - SwiftData

    var modelContext: ModelContext?

    // MARK: - Private State

    private var recordingURL: URL?
    private var durationTimer: Timer?
    private var audioEngine: AVAudioEngine?

    // MARK: - Initialization

    init(
        locationService: LocationService,
        audioService: AudioService,
        transcriptionService: TranscriptionService,
        geocodingService: ReverseGeocodingService = ReverseGeocodingService(),
        geofenceManager: GeofenceManager = .shared,
        subscriptionService: SubscriptionService = SubscriptionService()
    ) {
        self.locationService = locationService
        self.audioService = audioService
        self.transcriptionService = transcriptionService
        self.geocodingService = geocodingService
        self.geofenceManager = geofenceManager
        self.subscriptionService = subscriptionService
    }

    // MARK: - Recording Flow

    func startRecording() async {
        guard !isRecording else { return }

        // Check free tier loci limit
        if let modelContext,
           !TierEnforcement.canCreateLocus(tier: subscriptionService.currentTier, modelContext: modelContext) {
            blockedFeature = .lociLimit
            return
        }

        isPreparing = true
        errorMessage = nil

        // Validate microphone permission
        let micGranted = await audioService.requestMicrophonePermission()
        guard micGranted else {
            isPreparing = false
            errorMessage = String(localized: "Microphone access is required to record voice notes. Please enable it in Settings.")
            return
        }

        // Validate location permission
        guard locationService.isAuthorized else {
            isPreparing = false
            errorMessage = String(localized: "Location access is required to pin voice notes. Please enable it in Settings.")
            return
        }

        // Request transcription permission (non-blocking — recording works without it)
        await transcriptionService.requestTranscriptionPermission()

        // Start audio recording
        do {
            let url = try audioService.startRecording()
            recordingURL = url
        } catch {
            isPreparing = false
            errorMessage = String(localized: "Failed to start recording. Please try again.")
            return
        }

        // Start live transcription if available
        if transcriptionService.isAvailable {
            do {
                let engine = AVAudioEngine()
                audioEngine = engine
                try transcriptionService.startLiveTranscription(audioEngine: engine)
            } catch {
                // Transcription failure is non-fatal — recording continues
                audioEngine = nil
            }
        }

        isPreparing = false
        isRecording = true
        recordingDuration = 0
        startDurationTimer()
        AnalyticsService.shared.trackRecordingStarted()
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Recording started"))
    }

    /// Stops recording and returns the audio URL, transcription text, and captured coordinate.
    /// Returns `nil` if recording was not active or location is unavailable.
    func stopRecording() async -> (url: URL, transcription: String, coordinate: CLLocationCoordinate2D)? {
        guard isRecording else { return nil }

        UIAccessibility.post(notification: .announcement, argument: String(localized: "Recording stopped"))

        // Stop services
        audioService.stopRecording()
        transcriptionService.stopLiveTranscription()
        stopDurationTimer()

        if let engine = audioEngine {
            engine.stop()
            audioEngine = nil
        }

        isRecording = false

        guard let url = recordingURL else { return nil }

        // Capture final transcription — if live transcription was empty, try file-based
        var finalTranscription = transcription
        if finalTranscription.isEmpty, transcriptionService.isAvailable {
            finalTranscription = (try? await transcriptionService.transcribeFile(url: url)) ?? ""
        }

        // Capture coordinate
        guard let coordinate = currentLocation?.coordinate else {
            errorMessage = String(localized: "Unable to determine your location. The voice note was saved but may not have an accurate position.")
            return (url: url, transcription: finalTranscription, coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))
        }

        return (url: url, transcription: finalTranscription, coordinate: coordinate)
    }

    /// Cancels an in-progress recording and deletes the audio file.
    func cancelRecording() {
        guard isRecording else { return }

        audioService.stopRecording()
        transcriptionService.stopLiveTranscription()
        stopDurationTimer()

        if let engine = audioEngine {
            engine.stop()
            audioEngine = nil
        }

        if let url = recordingURL {
            audioService.deleteRecording(at: url)
        }

        isRecording = false
        recordingDuration = 0
        recordingURL = nil
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func clearBlockedFeature() {
        blockedFeature = nil
    }

    // MARK: - Save Flow

    /// Saves a recorded locus to SwiftData, reverse geocodes its location, auto-categorizes
    /// the transcription, refreshes geofences, and fires a success haptic.
    ///
    /// US-177: Geocoding and keyword categorization now run off the main actor with a
    /// 2-second timeout on geocoding; if the network is slow, the locus is saved
    /// immediately with a nil locationName and the name is patched in a follow-up task.
    func saveLocus(
        audioURL: URL,
        transcription: String,
        coordinate: CLLocationCoordinate2D,
        category: LocusCategory,
        isShared: Bool,
        householdId: UUID? = nil,
        createdByName: String? = nil
    ) async {
        guard let modelContext else {
            errorMessage = String(localized: "Unable to save. Please try again.")
            return
        }

        isSaving = true

        // US-177: Bounded reverse geocode — never block the save by more than 2s.
        let locationName = await Self.geocodeWithTimeout(
            coordinate: coordinate,
            geocodingService: geocodingService,
            timeout: .seconds(2)
        )

        // US-177: Keyword categorization runs off the main actor.
        let finalCategory: LocusCategory
        if category == .general {
            finalCategory = await Task.detached(priority: .userInitiated) {
                AICategoryService.categorize(transcription: transcription)
            }.value
        } else {
            finalCategory = category
        }

        // Create and insert Locus into SwiftData
        let locus = Locus(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            locationName: locationName,
            audioFileURL: audioURL.lastPathComponent,
            transcription: InputSanitizer.sanitizeTranscription(transcription),
            category: finalCategory,
            isShared: isShared,
            createdByName: isShared ? createdByName.map { InputSanitizer.sanitizeDisplayName($0) } : nil,
            householdId: isShared ? householdId : nil
        )

        modelContext.insert(locus)

        do {
            try modelContext.save()
        } catch {
            isSaving = false
            errorMessage = String(localized: "Failed to save voice note. Please try again.")
            return
        }

        // US-177: If geocoding timed out, patch the location name in the background
        // so the UI feels instant but the final locus still gets a readable label.
        if locationName == nil {
            let locusID = locus.id
            let geocoder = geocodingService
            Task.detached(priority: .utility) { [weak self] in
                guard let late = try? await geocoder.reverseGeocode(coordinate),
                      let self else { return }
                await self.applyLateLocationName(late, to: locusID)
            }
        }

        // Notify the geofence system about the new locus
        NotificationCenter.default.post(name: .locusDidCreate, object: nil)

        // US-178: Nudge the widget so its hourly refresh cadence never leaves the
        // "Nearby Loci" list visibly stale after a fresh recording.
        WidgetCenter.shared.reloadAllTimelines()

        // Success haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        AnalyticsService.shared.trackRecordingCompleted()
        AnalyticsService.shared.trackLocusCreated(category: finalCategory.rawValue)

        isSaving = false
        didSaveLocus = true
    }

    /// Patches the locationName of a previously-saved Locus if the deferred geocode
    /// completes after the save. Runs on the main actor so SwiftData mutations are
    /// serialized.
    @MainActor
    private func applyLateLocationName(_ name: String, to locusID: UUID) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate<Locus> { $0.id == locusID }
        )
        guard let match = try? modelContext.fetch(descriptor).first else { return }
        match.locationName = name
        match.updatedAt = Date()
        try? modelContext.save()
    }

    /// US-177: Races the reverse-geocode call against a deadline. Returns `nil` if
    /// the deadline elapses — the caller saves immediately and patches the name later.
    private static func geocodeWithTimeout(
        coordinate: CLLocationCoordinate2D,
        geocodingService: ReverseGeocodingService,
        timeout: Duration
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                try? await geocodingService.reverseGeocode(coordinate)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            if let first = await group.next() { return first }
            return nil
        }
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.recordingDuration += 1

            // Auto-stop at max duration
            if self.recordingDuration >= AppConstants.maxRecordingDurationSeconds {
                self.didReachMaxDuration = true
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
