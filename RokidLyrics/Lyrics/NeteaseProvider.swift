import Foundation
import CommonCrypto
import Security

final class NeteaseProvider {
    private let session = URLSession.shared
    private let searchURL = "https://music.163.com/weapi/search/get"
    private let lyricURL = "https://music.163.com/weapi/song/lyric"

    // Netease weapi constants
    private let nonce = "0CoJUm6Qyw8W8jud"
    private let iv = "0102030405060708"
    private let rsaPublicKey = "00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7"
    private let rsaExp = "010001"

    func fetch(_ request: LyricsLookupRequest) async -> FetchedLyrics? {
        // Prepare title (strip feat)
        let cleanTitle = stripFeat(request.title)

        guard let trackId = await searchTrack(title: cleanTitle, artist: request.artist) else { return nil }
        return await fetchLyric(trackId: trackId)
    }

    private func searchTrack(title: String, artist: String) async -> Int? {
        let query = "\(title) \(artist)"
        let params: [String: Any] = ["s": query, "type": 1, "limit": 5, "offset": 0]
        guard let data = try? await weapi(searchURL, params: params),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]],
              let first = songs.first,
              let id = first["id"] as? Int else { return nil }
        return id
    }

    private func fetchLyric(trackId: Int) async -> FetchedLyrics? {
        let params: [String: Any] = ["id": trackId, "lv": -1, "kv": -1, "tv": -1]
        guard let data = try? await weapi(lyricURL, params: params),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Try synced LRC first
        if let lrc = (json["lrc"] as? [String: Any])?["lyric"] as? String, !lrc.isEmpty {
            let lines = parseLRC(lrc)
            let filtered = lines.filter { !isCreditLine($0.text) }
            if !filtered.isEmpty {
                return FetchedLyrics(lines: filtered, plainLyrics: lrc, synced: true, provider: "Netease")
            }
        }
        // Karaoke fallback
        if let klyric = (json["klyric"] as? [String: Any])?["lyric"] as? String, !klyric.isEmpty {
            let lines = parseLRC(klyric)
            let filtered = lines.filter { !isCreditLine($0.text) }
            if !filtered.isEmpty {
                return FetchedLyrics(lines: filtered, plainLyrics: klyric, synced: true, provider: "Netease")
            }
        }
        return nil
    }

    // MARK: - weapi encryption

    private func weapi(_ urlString: String, params: [String: Any]) async throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: params)
        let jsonStr = String(data: jsonData, encoding: .utf8)!

        // Generate 16-byte random key
        var randomKeyBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &randomKeyBytes)
        let randomKey = String(randomKeyBytes.map { "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        // Use fixed chars for compatibility
        let keyChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomKeyStr = String((0..<16).map { _ in keyChars.randomElement()! })

        let params1 = aesCBC(data: jsonStr.data(using: .utf8)!, key: nonce, iv: iv)!
        let params2 = aesCBC(data: params1, key: randomKeyStr, iv: iv)!
        let encParams = params2.base64EncodedString()
        let encKey = rsaEncrypt(randomKeyStr.reversed().description.replacingOccurrences(of: "ReversedCollection<String.SubSequence>", with: ""))

        // Simpler approach: reverse the string manually
        let reversedKey = String(randomKeyStr.reversed())
        let encKey2 = rsaEncryptString(reversedKey)

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let body = "params=\(encParams.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&encSecKey=\(encKey2.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        return data
    }

    private func aesCBC(data: Data, key: String, iv: String) -> Data? {
        let keyData = key.data(using: .utf8)!
        let ivData = iv.data(using: .utf8)!
        let dataLen = data.count
        let bufLen = dataLen + kCCBlockSizeAES128
        var buf = [UInt8](repeating: 0, count: bufLen)
        var numOut = 0
        let status = data.withUnsafeBytes { dataPtr in
            keyData.withUnsafeBytes { keyPtr in
                ivData.withUnsafeBytes { ivPtr in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, keyData.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, dataLen,
                            &buf, bufLen, &numOut)
                }
            }
        }
        return status == kCCSuccess ? Data(buf.prefix(numOut)) : nil
    }

    private func rsaEncryptString(_ text: String) -> String {
        // RSA with public key: e=010001, n=rsaPublicKey (hex modular exponentiation)
        // Encode text as hex, then modPow using BigUInt-style approach
        let textHex = text.data(using: .utf8)!.map { String(format: "%02x", $0) }.joined()
        guard !textHex.isEmpty else { return "" }
        let result = modPow(base: textHex, exp: rsaExp, mod: rsaPublicKey)
        // Pad to 256 chars
        return String(repeating: "0", count: max(0, 256 - result.count)) + result
    }

    // Big-integer hex modular exponentiation (schoolbook, fine for 256-byte RSA key lookup)
    private func modPow(base: String, exp: String, mod: String) -> String {
        var b = BigHex(hex: base)
        var e = BigHex(hex: exp)
        let m = BigHex(hex: mod)
        var result = BigHex(value: 1)
        b = b.mod(m)
        while !e.isZero {
            if e.isOdd {
                result = result.mul(b).mod(m)
            }
            e = e.shiftRight1()
            b = b.mul(b).mod(m)
        }
        return result.toHex()
    }

    // MARK: - Helpers

    private func stripFeat(_ title: String) -> String {
        let patterns = [#" \(feat\.[^)]*\)"#, #" feat\.[^\[]*"#, #" ft\.[^\[]*"#]
        var result = title
        for p in patterns {
            result = result.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func isCreditLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        let creditPatterns = ["作词", "作曲", "编曲", "制作", "词:", "曲:", "producers", "lyrics by", "music by", "arranged by"]
        return creditPatterns.contains { lower.contains($0) }
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

    // Needed to silence unused-warning; actual call is rsaEncryptString
    private func rsaEncrypt(_ s: String) -> String { rsaEncryptString(s) }
}

// MARK: - Minimal big-integer for RSA (hex string representation)

private struct BigHex {
    var digits: [UInt32] // base-2^32 limbs, least significant first

    init(value: UInt32) { digits = [value] }

    init(hex: String) {
        // Pad to multiple of 8
        let padded = hex.count % 8 == 0 ? hex : String(repeating: "0", count: 8 - hex.count % 8) + hex
        var d: [UInt32] = []
        var i = padded.endIndex
        while i > padded.startIndex {
            let start = padded.index(i, offsetBy: -8, limitedBy: padded.startIndex) ?? padded.startIndex
            d.append(UInt32(padded[start..<i], radix: 16) ?? 0)
            i = start
        }
        digits = d
        trim()
    }

    mutating func trim() {
        while digits.count > 1 && digits.last == 0 { digits.removeLast() }
    }

    var isZero: Bool { digits.allSatisfy { $0 == 0 } }
    var isOdd: Bool { (digits.first ?? 0) & 1 == 1 }

    func shiftRight1() -> BigHex {
        var result = digits
        var carry: UInt32 = 0
        for i in stride(from: result.count - 1, through: 0, by: -1) {
            let newCarry = result[i] & 1
            result[i] = (result[i] >> 1) | (carry << 31)
            carry = newCarry
        }
        var r = BigHex(value: 0)
        r.digits = result
        r.trim()
        return r
    }

    func mul(_ other: BigHex) -> BigHex {
        var result = [UInt64](repeating: 0, count: digits.count + other.digits.count)
        for i in 0..<digits.count {
            for j in 0..<other.digits.count {
                result[i + j] += UInt64(digits[i]) * UInt64(other.digits[j])
                if result[i + j] >= (1 << 32) {
                    result[i + j + 1] += result[i + j] >> 32
                    result[i + j] &= 0xFFFFFFFF
                }
            }
        }
        // Carry propagation
        for i in 0..<result.count - 1 {
            result[i + 1] += result[i] >> 32
            result[i] &= 0xFFFFFFFF
        }
        var r = BigHex(value: 0)
        r.digits = result.map { UInt32($0 & 0xFFFFFFFF) }
        r.trim()
        return r
    }

    func mod(_ m: BigHex) -> BigHex {
        // Simple subtraction-based mod for small numbers; use division for large
        if compare(m) < 0 { return self }
        // Long division remainder
        var rem = self
        while rem.compare(m) >= 0 {
            rem = rem.sub(m)
        }
        return rem
    }

    func sub(_ other: BigHex) -> BigHex {
        var result = digits
        var borrow: Int64 = 0
        for i in 0..<max(result.count, other.digits.count) {
            let a: Int64 = i < result.count ? Int64(result[i]) : 0
            let b: Int64 = i < other.digits.count ? Int64(other.digits[i]) : 0
            let diff = a - b - borrow
            borrow = diff < 0 ? 1 : 0
            let val = diff < 0 ? diff + Int64(1) << 32 : diff
            if i < result.count { result[i] = UInt32(val) } else { result.append(UInt32(val)) }
        }
        var r = BigHex(value: 0)
        r.digits = result
        r.trim()
        return r
    }

    func compare(_ other: BigHex) -> Int {
        if digits.count != other.digits.count {
            return digits.count < other.digits.count ? -1 : 1
        }
        for i in stride(from: digits.count - 1, through: 0, by: -1) {
            if digits[i] != other.digits[i] { return digits[i] < other.digits[i] ? -1 : 1 }
        }
        return 0
    }

    func toHex() -> String {
        let parts = digits.reversed().map { String(format: "%08x", $0) }
        return parts.joined().replacingOccurrences(of: "^0+", with: "", options: .regularExpression).isEmpty ? "0" :
            parts.joined().replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
    }
}
