import AVFoundation
import Foundation

enum AppConstants {
    // MARK: - Free Tier Limits
    static let maxFreeLocis = 10

    // MARK: - Geofencing
    static let geofenceRadius: Double = 100.0
    static let maxGeofences = 20

    // MARK: - Household
    static let maxHouseholdMembers = 6
    static let inviteCodeLength = 6
    static let inviteExpiryHours = 48

    // MARK: - Recording Limits
    static let maxRecordingDurationSeconds: TimeInterval = 300 // 5 minutes
    static let lowStorageThresholdBytes: Int64 = 100 * 1024 * 1024 // 100 MB

    // MARK: - Session Security (US-145)
    static let sessionInactivityTimeoutDays: Int = 30
    static let tokenRefreshMaxRetries: Int = 3
    static let sessionActivityUpdateIntervalSeconds: TimeInterval = 300 // 5 minutes

    // MARK: - Audio Format
    enum Audio {
        static let formatID = kAudioFormatMPEG4AAC
        static let sampleRate: Double = 44100.0
        static let numberOfChannels: Int = 1
        static let bitRate = 64000
        static let fileExtension = "m4a"

        static var recorderSettings: [String: Any] {
            [
                AVFormatIDKey: formatID,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: numberOfChannels,
                AVEncoderBitRateKey: bitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
        }
    }
}
