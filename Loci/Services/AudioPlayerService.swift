import AVFoundation
import Foundation

@Observable
final class AudioPlayerService: NSObject, AVAudioPlayerDelegate {
    // MARK: - Properties

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var progress: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    // MARK: - Playback Controls

    func play(url: URL) {
        if let player = audioPlayer, player.url == url {
            player.play()
            isPlaying = true
            startProgressTimer()
            return
        }

        stop()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player

            duration = player.duration
            currentTime = 0
            progress = 0

            player.play()
            isPlaying = true
            startProgressTimer()
        } catch {
            reset()
        }
    }

    func pause() {
        guard let player = audioPlayer, player.isPlaying else { return }
        player.pause()
        isPlaying = false
        stopProgressTimer()
        updateProgress()
    }

    func stop() {
        audioPlayer?.stop()
        stopProgressTimer()
        reset()
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clampedTime = min(max(0, time), player.duration)
        player.currentTime = clampedTime
        updateProgress()
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopProgressTimer()
        isPlaying = false
        currentTime = duration
        progress = 1.0
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        stop()
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        duration = player.duration
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }

    // MARK: - Cleanup

    private func reset() {
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        progress = 0
    }

    deinit {
        stopProgressTimer()
        audioPlayer?.stop()
    }
}
