import Foundation

final class LrcLibClient {
    private let session = URLSession.shared
    private let baseURL = "https://lrclib.net"

    func fetch(_ request: LyricsLookupRequest) async -> FetchedLyrics? {
        // Strategy 1: cached endpoint
        if let result = await fetchCached(request) { return result }
        // Strategy 2: exact get
        if let result = await fetchExact(request) { return result }
        // Strategy 3: search + score
        return await fetchSearch(request)
    }

    private func fetchCached(_ req: LyricsLookupRequest) async -> FetchedLyrics? {
        var comps = URLComponents(string: "\(baseURL)/api/get-cached")!
        comps.queryItems = queryItems(req)
        guard let url = comps.url else { return nil }
        return await fetchAndParse(url, req)
    }

    private func fetchExact(_ req: LyricsLookupRequest) async -> FetchedLyrics? {
        var comps = URLComponents(string: "\(baseURL)/api/get")!
        comps.queryItems = queryItems(req)
        guard let url = comps.url else { return nil }
        return await fetchAndParse(url, req)
    }

    private func fetchSearch(_ req: LyricsLookupRequest) async -> FetchedLyrics? {
        var comps = URLComponents(string: "\(baseURL)/api/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: req.title),
            URLQueryItem(name: "artist_name", value: req.artist),
        ]
        guard let url = comps.url,
              let data = try? await session.data(from: url).0,
              let results = try? JSONDecoder().decode([LrcLibTrack].self, from: data) else { return nil }

        let best = results
            .map { ($0, candidateScore($0, req)) }
            .filter { $0.1 >= 55 }
            .max { $0.1 < $1.1 }

        return best.flatMap { parseLyrics($0.0) }
    }

    private func fetchAndParse(_ url: URL, _ req: LyricsLookupRequest) async -> FetchedLyrics? {
        guard let data = try? await session.data(from: url).0,
              let track = try? JSONDecoder().decode(LrcLibTrack.self, from: data) else { return nil }
        let score = candidateScore(track, req)
        if score < 55 { return nil }
        return parseLyrics(track)
    }

    private func queryItems(_ req: LyricsLookupRequest) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "track_name", value: req.title),
            URLQueryItem(name: "artist_name", value: req.artist),
        ]
        if !req.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: req.album))
        }
        if let dur = req.durationSeconds {
            items.append(URLQueryItem(name: "duration", value: "\(dur)"))
        }
        return items
    }

    private func candidateScore(_ track: LrcLibTrack, _ req: LyricsLookupRequest) -> Int {
        var score = 0
        let titleSim = similarity(track.trackName ?? "", req.title)
        let artistSim = similarity(track.artistName ?? "", req.artist)
        score += Int(titleSim * 3 * 100)
        score += Int(artistSim * 2 * 100)
        if !req.album.isEmpty {
            score += Int(similarity(track.albumName ?? "", req.album) * 50)
        }
        if let dur = req.durationSeconds, let trackDur = track.duration {
            let diff = abs(Double(dur) - trackDur)
            score += diff < 2 ? 100 : diff < 10 ? 50 : 0
        }
        if normalize(track.trackName ?? "") == normalize(req.title) { score += 100 }
        if normalize(track.artistName ?? "") == normalize(req.artist) { score += 80 }
        return score / 10
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a), nb = normalize(b)
        if na == nb { return 1.0 }
        if na.isEmpty || nb.isEmpty { return 0.0 }
        if na.contains(nb) || nb.contains(na) { return 0.8 }
        return 0.0
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseLyrics(_ track: LrcLibTrack) -> FetchedLyrics? {
        if let lrc = track.syncedLyrics, !lrc.isEmpty {
            let lines = parseLRC(lrc)
            if !lines.isEmpty {
                return FetchedLyrics(
                    lines: lines,
                    plainLyrics: track.plainLyrics ?? lrc,
                    synced: true,
                    provider: "LRCLib"
                )
            }
        }
        if let plain = track.plainLyrics, !plain.isEmpty {
            return FetchedLyrics(lines: [], plainLyrics: plain, synced: false, provider: "LRCLib")
        }
        return nil
    }

    private func parseLRC(_ lrc: String) -> [LyricsLine] {
        let pattern = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2}(?:\.\d+)?)\](.*)"#)
        var lines: [LyricsLine] = []
        for line in lrc.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern.firstMatch(in: line, range: range) else { continue }
            let mins = Int64((line as NSString).substring(with: match.range(at: 1))) ?? 0
            let secsStr = (line as NSString).substring(with: match.range(at: 2))
            let secs = Double(secsStr) ?? 0
            let text = (line as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            let ms = mins * 60_000 + Int64(secs * 1000)
            lines.append(LyricsLine(startTimeMs: ms, text: text))
        }
        return lines.sorted { $0.startTimeMs < $1.startTimeMs }
    }
}

private struct LrcLibTrack: Codable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?
}
