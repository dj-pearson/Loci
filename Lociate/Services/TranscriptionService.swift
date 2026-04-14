import AVFoundation
import Foundation
import Speech

@Observable
final class TranscriptionService {
    // MARK: - Properties

    private(set) var isAvailable = false
    private(set) var permissionStatus: PermissionStatus = .notDetermined
    private(set) var transcriptionError: TranscriptionError?
    private(set) var transcription: String = ""
    private(set) var isFinal = false
    private(set) var isTranscribing = false

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    private var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Permission Status

    enum PermissionStatus {
        case notDetermined
        case granted
        case denied
        case restricted

        init(from status: SFSpeechRecognizerAuthorizationStatus) {
            switch status {
            case .authorized:
                self = .granted
            case .denied:
                self = .denied
            case .restricted:
                self = .restricted
            case .notDetermined:
                self = .notDetermined
            @unknown default:
                self = .notDetermined
            }
        }
    }

    // MARK: - Initialization

    init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        permissionStatus = PermissionStatus(from: SFSpeechRecognizer.authorizationStatus())
        updateAvailability()
    }

    // MARK: - Permission

    func requestTranscriptionPermission() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            permissionStatus = .granted
            return true
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                let granted = status == .authorized
                self?.permissionStatus = PermissionStatus(from: status)
                self?.updateAvailability()
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Availability

    private func updateAvailability() {
        isAvailable = speechRecognizer?.isAvailable ?? false
                    && permissionStatus == .granted
    }

    // MARK: - Recognition Request Configuration

    func configureRecognitionRequest(_ request: SFSpeechRecognitionRequest) {
        if supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            // Fallback to server recognition when on-device is unavailable
            request.requiresOnDeviceRecognition = false
        }

        request.shouldReportPartialResults = true

        if #available(iOS 18.0, *) {
            request.addsPunctuation = true
        }
    }

    // MARK: - Live Streaming Transcription

    func startLiveTranscription(audioEngine: AVAudioEngine) throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            let error = TranscriptionError.recognizerUnavailable
            transcriptionError = error
            throw error
        }

        guard permissionStatus == .granted else {
            let error = TranscriptionError.permissionDenied
            transcriptionError = error
            throw error
        }

        // Cancel any existing task
        stopLiveTranscription()

        self.audioEngine = audioEngine
        transcription = ""
        isFinal = false
        transcriptionError = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        configureRecognitionRequest(request)
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.transcription = result.bestTranscription.formattedString
                self.isFinal = result.isFinal

                if result.isFinal {
                    self.isTranscribing = false
                }
            }

            if let error {
                // Ignore cancellation errors from intentional stop
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // Recognition request was canceled — not a real error
                    return
                }

                self.transcriptionError = .recognitionFailed(error.localizedDescription)
                self.isTranscribing = false
            }
        }

        // Install audio tap on the input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                stopLiveTranscription()
                let engineError = TranscriptionError.audioEngineError(error.localizedDescription)
                transcriptionError = engineError
                throw engineError
            }
        }

        isTranscribing = true
    }

    func stopLiveTranscription() {
        // Remove the tap before stopping the engine
        if let engine = audioEngine, engine.inputNode.numberOfInputs > 0 {
            engine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine = nil
        isTranscribing = false
    }

    // MARK: - File Transcription

    func transcribeFile(url: URL) async throws -> String {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            let error = TranscriptionError.recognizerUnavailable
            transcriptionError = error
            throw error
        }

        guard permissionStatus == .granted else {
            let error = TranscriptionError.permissionDenied
            transcriptionError = error
            throw error
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        configureRecognitionRequest(request)

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let result else { return }

                if result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - Error Types

    enum TranscriptionError: Error, Equatable {
        case recognizerUnavailable
        case permissionDenied
        case recognitionFailed(String)
        case audioEngineError(String)

        var localizedDescription: String {
            switch self {
            case .recognizerUnavailable:
                String(localized: "Speech recognition is not available on this device.")
            case .permissionDenied:
                String(localized: "Speech recognition permission has been denied. Please enable it in Settings.")
            case .recognitionFailed(let message):
                String(localized: "Speech recognition failed: \(message)")
            case .audioEngineError(let message):
                String(localized: "Audio engine error: \(message)")
            }
        }
    }
}
