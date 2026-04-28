import Foundation

@MainActor
final class LyricsRuntimeEngine: ObservableObject {
    @Published private(set) var snapshot: LyricsSnapshot = LyricsSnapshot()

    private let provider = CompositeLyricsProvider()
    private var generation: Int = 0
    private var lastLookupRequest: LyricsLookupRequest? = nil
    private var fetchedLyrics: FetchedLyrics? = nil
    private var lastErrorTime: Date? = nil

    private let driftToleranceMs: Int64 = 1500
    private let errorRetryInterval: TimeInterval = 15

    func update(media: MediaPlaybackSnapshot?) {
        guard let media else {
            if snapshot.sessionState != .idle {
                snapshot = LyricsSnapshot(
                    sessionState: .idle,
                    sourceSummary: "Waiting for active media playback on the phone."
                )
                fetchedLyrics = nil
                lastLookupRequest = nil
            }
            return
        }

        let req = LyricsLookupRequest(
            title: media.title,
            artist: media.artist,
            album: media.album,
            durationSeconds: media.durationSeconds
        )

        if shouldLookup(req, media: media) {
            triggerLookup(req, media: media)
        } else {
            syncProgress(media: media)
        }
    }

    private func shouldLookup(_ req: LyricsLookupRequest, media: MediaPlaybackSnapshot) -> Bool {
        guard let last = lastLookupRequest else { return true }
        if req.title != last.title || req.artist != last.artist { return true }
        if snapshot.sessionState == .error {
            if let t = lastErrorTime, Date().timeIntervalSince(t) >= errorRetryInterval { return true }
        }
        return false
    }

    private func triggerLookup(_ req: LyricsLookupRequest, media: MediaPlaybackSnapshot) {
        generation += 1
        let gen = generation
        lastLookupRequest = req
        lastErrorTime = nil

        snapshot = LyricsSnapshot(
            sessionState: .loading,
            trackTitle: media.title,
            artistName: media.artist,
            albumName: media.album,
            durationSeconds: media.durationSeconds,
            sourceSummary: "Looking up lyrics…"
        )

        Task {
            let result = await provider.fetch(req)
            guard gen == generation else { return }
            if let lyrics = result {
                fetchedLyrics = lyrics
                let lineIndex = indexForProgress(ms: media.positionMs, lines: lyrics.lines)
                snapshot = LyricsSnapshot(
                    sessionState: media.isPlaying ? .playing : .ready,
                    trackTitle: media.title,
                    artistName: media.artist,
                    albumName: media.album,
                    durationSeconds: media.durationSeconds,
                    provider: lyrics.provider,
                    sourceSummary: "\(lyrics.provider) · \(media.title)",
                    synced: lyrics.synced,
                    progressMs: media.positionMs,
                    capturedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                    currentLineIndex: lineIndex,
                    lines: lyrics.lines,
                    plainLyrics: lyrics.plainLyrics
                )
            } else {
                lastErrorTime = Date()
                fetchedLyrics = nil
                snapshot = LyricsSnapshot(
                    sessionState: .error,
                    trackTitle: media.title,
                    artistName: media.artist,
                    albumName: media.album,
                    durationSeconds: media.durationSeconds,
                    sourceSummary: "Lyrics not found.",
                    errorMessage: "No lyrics found for this track."
                )
            }
        }
    }

    private func syncProgress(media: MediaPlaybackSnapshot) {
        guard let lyrics = fetchedLyrics else { return }
        let lineIndex = indexForProgress(ms: media.positionMs, lines: lyrics.lines)
        let state: LyricsSessionState = media.isPlaying ? .playing : .ready

        let driftMs = abs(snapshot.progressMs - media.positionMs)
        let lineChanged = lineIndex != snapshot.currentLineIndex
        let stateChanged = state != snapshot.sessionState

        if stateChanged || lineChanged || driftMs >= driftToleranceMs {
            snapshot = LyricsSnapshot(
                sessionState: state,
                trackTitle: snapshot.trackTitle,
                artistName: snapshot.artistName,
                albumName: snapshot.albumName,
                durationSeconds: snapshot.durationSeconds,
                provider: snapshot.provider,
                sourceSummary: snapshot.sourceSummary,
                synced: snapshot.synced,
                progressMs: media.positionMs,
                capturedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                currentLineIndex: lineIndex,
                lines: snapshot.lines,
                plainLyrics: snapshot.plainLyrics
            )
        }
    }

    private func indexForProgress(ms: Int64, lines: [LyricsLine]) -> Int {
        guard !lines.isEmpty else { return -1 }
        var lo = 0, hi = lines.count - 1, result = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].startTimeMs <= ms {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    func currentSnapshot(capturedAt: Int64) -> LyricsSnapshot {
        snapshot
    }

    func syncSnapshot(capturedAt: Int64) -> LyricsPlaybackSync {
        LyricsPlaybackSync(
            sessionState: snapshot.sessionState,
            progressMs: snapshot.progressMs,
            capturedAtEpochMs: capturedAt,
            currentLineIndex: snapshot.currentLineIndex
        )
    }
}
