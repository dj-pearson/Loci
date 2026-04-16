import AVFoundation
import Foundation
import UIKit

@Observable
final class AudioService {
    // MARK: - Properties

    private(set) var isRecording = false
    private(set) var currentRecordingURL: URL?
    private(set) var currentAmplitude: Float = 0.0
    private(set) var audioError: AudioError?
    private(set) var permissionStatus: PermissionStatus = .notDetermined

    private var audioRecorder: AVAudioRecorder?
    private let audioSession = AVAudioSession.sharedInstance()
    private var amplitudeTimer: Timer?

    // MARK: - Permission Status

    enum PermissionStatus {
        case notDetermined
        case granted
        case denied

        init(from recordPermission: AVAudioSession.RecordPermission) {
            switch recordPermission {
            case .granted:
                self = .granted
            case .denied:
                self = .denied
            case .undetermined:
                self = .notDetermined
            @unknown default:
                self = .notDetermined
            }
        }
    }

    // MARK: - Initialization

    init() {
        permissionStatus = PermissionStatus(from: audioSession.recordPermission)
    }

    // MARK: - Audio Session Configuration

    func configureAudioSession() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker]
        )
        try audioSession.setActive(true)
    }

    // MARK: - Microphone Permission

    func requestMicrophonePermission() async -> Bool {
        if audioSession.recordPermission == .granted {
            permissionStatus = .granted
            return true
        }

        let granted = await AVAudioApplication.requestRecordPermission()
        permissionStatus = granted ? .granted : .denied
        return granted
    }

    // MARK: - Recording URL Generation

    func generateRecordingURL() -> URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let uuid = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "locus_\(uuid)_\(timestamp).\(AppConstants.Audio.fileExtension)"

        return documentsDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Recorder Preparation

    func prepareRecorder() throws -> URL {
        let url = generateRecordingURL()

        do {
            try configureAudioSession()
        } catch {
            audioError = .sessionConfigurationFailed(error.localizedDescription)
            throw AudioError.sessionConfigurationFailed(error.localizedDescription)
        }

        do {
            audioRecorder = try AVAudioRecorder(
                url: url,
                settings: AppConstants.Audio.recorderSettings
            )
            audioRecorder?.prepareToRecord()
            currentRecordingURL = url
            return url
        } catch {
            audioError = .recorderCreationFailed(error.localizedDescription)
            throw AudioError.recorderCreationFailed(error.localizedDescription)
        }
    }

    // MARK: - Recording Controls

    @discardableResult
    func startRecording() throws -> URL {
        guard permissionStatus == .granted else {
            audioError = .microphonePermissionDenied
            throw AudioError.microphonePermissionDenied
        }

        let url = try prepareRecorder()

        guard let recorder = audioRecorder else {
            audioError = .recordingFailed("Recorder not available")
            throw AudioError.recordingFailed("Recorder not available")
        }

        recorder.isMeteringEnabled = true
        recorder.record()
        isRecording = true

        startAmplitudeTimer()

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        return url
    }

    func stopRecording() {
        guard isRecording, let recorder = audioRecorder else { return }

        recorder.stop()
        stopAmplitudeTimer()
        isRecording = false
        currentAmplitude = 0.0

        // Encrypt the recorded audio file at rest
        if let url = currentRecordingURL {
            try? AudioEncryptionService.encryptFile(at: url)
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Amplitude Metering

    private func startAmplitudeTimer() {
        amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateAmplitude()
        }
    }

    private func stopAmplitudeTimer() {
        amplitudeTimer?.invalidate()
        amplitudeTimer = nil
    }

    private func updateAmplitude() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            currentAmplitude = 0.0
            return
        }

        recorder.updateMeters()

        // averagePower returns dB in range [-160, 0]. Normalize to [0, 1].
        let power = recorder.averagePower(forChannel: 0)
        let minDb: Float = -60.0
        let normalizedPower = max(0.0, (power - minDb) / (-minDb))
        currentAmplitude = normalizedPower
    }

    // MARK: - Cleanup

    func cleanup() {
        stopAmplitudeTimer()
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        currentAmplitude = 0.0
        currentRecordingURL = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Error Types

    enum AudioError: Equatable {
        case microphonePermissionDenied
        case sessionConfigurationFailed(String)
        case recorderCreationFailed(String)
        case recordingFailed(String)

        var localizedDescription: String {
            switch self {
            case .microphonePermissionDenied:
                String(localized: "Microphone access has been denied. Please enable it in Settings to record voice notes.")
            case .sessionConfigurationFailed(let message):
                String(localized: "Failed to configure audio session: \(message)")
            case .recorderCreationFailed(let message):
                String(localized: "Failed to create audio recorder: \(message)")
            case .recordingFailed(let message):
                String(localized: "Recording failed: \(message)")
            }
        }
    }
}
