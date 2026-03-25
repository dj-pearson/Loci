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
