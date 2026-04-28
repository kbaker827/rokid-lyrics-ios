import Foundation

final class CompositeLyricsProvider {
    private let musixmatch = MusixmatchProvider()
    private let netease = NeteaseProvider()
    private let lrclib = LrcLibClient()

    func fetch(_ request: LyricsLookupRequest) async -> FetchedLyrics? {
        if let result = await musixmatch.fetch(request) { return result }
        if let result = await netease.fetch(request) { return result }
        return await lrclib.fetch(request)
    }
}
