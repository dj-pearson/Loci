import AVFoundation
import CoreLocation
import Foundation
import SwiftData
import UIKit

@Observable
final class RecordViewModel {
    // MARK: - State

    private(set) var isRecording = false
    private(set) var isPreparing = false
    private(set) var isSaving = false
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var errorMessage: String?
    private(set) var didSaveLocus = false

    var transcription: String {
        transcriptionService.transcription
    }

    var amplitude: Float {
        audioService.currentAmplitude
    }

    var currentLocation: CLLocation? {
        locationService.currentLocation
    }

    // MARK: - Dependencies

    private let locationService: LocationService
    private let audioService: AudioService
    private let transcriptionService: TranscriptionService
    private let geocodingService: ReverseGeocodingService
    private let geofenceManager: GeofenceManager

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
        geofenceManager: GeofenceManager = .shared
    ) {
        self.locationService = locationService
        self.audioService = audioService
        self.transcriptionService = transcriptionService
        self.geocodingService = geocodingService
        self.geofenceManager = geofenceManager
    }

    // MARK: - Recording Flow

    func startRecording() async {
        guard !isRecording else { return }

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
    }

    /// Stops recording and returns the audio URL, transcription text, and captured coordinate.
    /// Returns `nil` if recording was not active or location is unavailable.
    func stopRecording() async -> (url: URL, transcription: String, coordinate: CLLocationCoordinate2D)? {
        guard isRecording else { return nil }

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

    // MARK: - Save Flow

    /// Saves a recorded locus to SwiftData, reverse geocodes its location, auto-categorizes
    /// the transcription, refreshes geofences, and fires a success haptic.
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

        // Reverse geocode location name (best-effort, non-blocking on failure)
        let locationName = try? await geocodingService.reverseGeocode(coordinate)

        // Auto-categorize if the user kept the default general category
        let finalCategory: LocusCategory
        if category == .general {
            finalCategory = AICategoryService.categorize(transcription: transcription)
        } else {
            finalCategory = category
        }

        // Create and insert Locus into SwiftData
        let locus = Locus(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            locationName: locationName,
            audioFileURL: audioURL.lastPathComponent,
            transcription: transcription,
            category: finalCategory,
            isShared: isShared,
            createdByName: isShared ? createdByName : nil,
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

        // Notify the geofence system about the new locus
        NotificationCenter.default.post(name: .locusDidCreate, object: nil)

        // Success haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        isSaving = false
        didSaveLocus = true
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.recordingDuration += 1
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
