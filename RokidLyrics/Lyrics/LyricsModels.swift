import Foundation

struct LyricsLookupRequest {
    let title: String
    let artist: String
    let album: String
    let durationSeconds: Int?
}

struct FetchedLyrics {
    let lines: [LyricsLine]
    let plainLyrics: String
    let synced: Bool
    let provider: String
}
