import Foundation
import CommonCrypto

final class MusixmatchProvider {
    private let session = URLSession.shared
    private let signingKey = "IEJ5E8XFaHQvIQNfs7IC"
    private let baseURL = "https://apic-desktop.musixmatch.com/ws/1.1"
    private let appId = "mac2-webapp-v1.0"

    private var sessionToken: String? = nil
    private var sessionTokenExpiry: Date = .distantPast
    private let tokenLifetime: TimeInterval = 600

    func fetch(_ request: LyricsLookupRequest) async -> FetchedLyrics? {
        if sessionToken == nil || Date() >= sessionTokenExpiry {
            await refreshSession()
        }
        guard sessionToken != nil else { return nil }

        // Try matcher.track.get (exact match)
        if let result = await matcherTrackGet(request) { return result }

        // Try macro.search (fuzzy)
        return await macroSearch(request)
    }

    private func refreshSession() async {
        // Step 1: get token
        guard let tokenUrl = signedURL("token.get", params: ["user_language": "en", "app_id": appId]) else { return }
        guard let data = try? await session.data(from: tokenUrl).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let body = message["body"] as? [String: Any],
              let token = body["user_token"] as? String else { return }

        // Step 2: validate credentials
        guard let credUrl = signedURL("credential.post", params: ["app_id": appId]) else { return }
        var credReq = URLRequest(url: credUrl)
        credReq.httpMethod = "POST"
        credReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        credReq.httpBody = try? JSONSerialization.data(withJSONObject: ["user_token": token])
        _ = try? await session.data(for: credReq)

        sessionToken = token
        sessionTokenExpiry = Date().addingTimeInterval(tokenLifetime)
    }

    private func matcherTrackGet(_ req: LyricsLookupRequest) async -> FetchedLyrics? {
        var params: [String: String] = [
            "app_id": appId,
            "q_track": req.title,
            "q_artist": req.artist,
        ]
        if let dur = req.durationSeconds { params["q_duration"] = "\(dur)" }
        if let tok = sessionToken { params["usertoken"] = tok }

        guard let url = signedURL("matcher.track.get", params: params),
              let data = try? await session.data(from: url).0 else { return nil }

        return extractTrackLyrics(data, req)
    }

    private func macroSearch(_ req: LyricsLookupRequest) async -> FetchedLyrics? {
        var params: [String: String] = [
            "app_id": appId,
            "q_track": req.title,
            "q_artist": req.artist,
            "q_lyrics": req.title,
            "page_size": "5",
            "page": "1",
            "f_has_lyrics": "1",
        ]
        if let tok = sessionToken { params["usertoken"] = tok }

        guard let url = signedURL("macro.search", params: params),
              let data = try? await session.data(from: url).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = json["message"] as? [String: Any],
              let body = msg["body"] as? [String: Any],
              let macroResult = body["macro_result_list"] as? [String: Any],
              let trackList = macroResult["track_list"] as? [[String: Any]] else { return nil }

        for item in trackList {
            guard let trackObj = item["track"] as? [String: Any],
                  let trackId = trackObj["track_id"] as? Int else { continue }
            if let result = await fetchSubtitle(trackId: trackId) { return result }
        }
        return nil
    }

    private func extractTrackLyrics(_ data: Data, _ req: LyricsLookupRequest) -> FetchedLyrics? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = json["message"] as? [String: Any],
              let body = msg["body"] as? [String: Any],
              let track = body["track"] as? [String: Any],
              let trackId = track["track_id"] as? Int else { return nil }
        return nil.flatMap { (_: Int?) -> FetchedLyrics? in nil } ?? { Task { return await fetchSubtitle(trackId: trackId) }; return nil }()
    }

    private func fetchSubtitle(trackId: Int) async -> FetchedLyrics? {
        var params: [String: String] = [
            "app_id": appId,
            "track_id": "\(trackId)",
            "subtitle_format": "lrc",
        ]
        if let tok = sessionToken { params["usertoken"] = tok }

        guard let url = signedURL("track.subtitle.get", params: params),
              let data = try? await session.data(from: url).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = json["message"] as? [String: Any],
              let body = msg["body"] as? [String: Any],
              let subtitleObj = body["subtitle"] as? [String: Any],
              let subtitleBody = subtitleObj["subtitle_body"] as? String,
              !subtitleBody.isEmpty else { return nil }

        let lines = parseLRC(subtitleBody)
        guard !lines.isEmpty else { return nil }
        return FetchedLyrics(lines: lines, plainLyrics: subtitleBody, synced: true, provider: "Musixmatch")
    }

    private func signedURL(_ endpoint: String, params: [String: String]) -> URL? {
        var comps = URLComponents(string: "\(baseURL)/\(endpoint)")!
        let timestamp = "\(Int(Date().timeIntervalSince1970))"
        var allParams = params
        allParams["timestamp"] = timestamp

        let sortedQuery = allParams.sorted { $0.key < $1.key }
            .map { "\($0.key)=\(urlEncode($0.value))" }
            .joined(separator: "&")
        let toSign = "\(baseURL)/\(endpoint)?\(sortedQuery)"
        let sig = hmacSHA1(message: toSign, key: signingKey)

        comps.percentEncodedQuery = sortedQuery + "&signature=\(urlEncode(sig))"
        return comps.url
    }

    private func hmacSHA1(message: String, key: String) -> String {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        let keyData = Array(key.utf8)
        let msgData = Array(message.utf8)
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), keyData, keyData.count, msgData, msgData.count, &result)
        return Data(result).base64EncodedString()
    }

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func parseLRC(_ lrc: String) -> [LyricsLine] {
        let pattern = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2}(?:\.\d+)?)\](.*)"#)
        var lines: [LyricsLine] = []
        for line in lrc.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern.firstMatch(in: line, range: range) else { continue }
            let mins = Int64((line as NSString).substring(with: match.range(at: 1))) ?? 0
            let secs = Double((line as NSString).substring(with: match.range(at: 2))) ?? 0
            let text = (line as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            lines.append(LyricsLine(startTimeMs: mins * 60_000 + Int64(secs * 1000), text: text))
        }
        return lines.sorted { $0.startTimeMs < $1.startTimeMs }
    }
}
