import Foundation
import MediaPlayer

struct MediaPlaybackSnapshot: Equatable {
    let title: String
    let artist: String
    let album: String
    let durationSeconds: Int?
    let positionMs: Int64
    let isPlaying: Bool
}

@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var snapshot: MediaPlaybackSnapshot? = nil
    @Published private(set) var statusMessage: String = "Waiting for active media playback."

    private var pollTimer: Timer?
    private var lastKnownSnapshot: MediaPlaybackSnapshot?

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func togglePlayback() {
        let player = MPMusicPlayerController.systemMusicPlayer
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    private func poll() {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            if snapshot != nil {
                snapshot = nil
                statusMessage = "No active media session found. Start a media app on the phone."
            }
            return
        }

        let title = (info[MPMediaItemPropertyTitle] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let artist = (info[MPMediaItemPropertyArtist] as? String
            ?? info[MPMediaItemPropertyAlbumArtist] as? String
            ?? "").trimmingCharacters(in: .whitespaces)

        guard !title.isEmpty, !artist.isEmpty else {
            snapshot = nil
            statusMessage = "Waiting for active media playback."
            return
        }

        let album = (info[MPMediaItemPropertyAlbumTitle] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let duration = info[MPMediaItemPropertyPlaybackDuration] as? Double
        let durationSec = duration.map { Int($0) }
        let elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0
        let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0
        let isPlaying = rate > 0

        let positionMs = Int64(elapsed * 1000)

        let newSnapshot = MediaPlaybackSnapshot(
            title: title,
            artist: artist,
            album: album,
            durationSeconds: durationSec,
            positionMs: positionMs,
            isPlaying: isPlaying
        )

        if newSnapshot != snapshot {
            snapshot = newSnapshot
            statusMessage = "Tracking \(title) / \(artist)"
        }
    }
}
