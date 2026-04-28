import Foundation

enum ConnectionState: String, Codable {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
}

struct DeviceStatus: Codable {
    var connectionState: ConnectionState = .disconnected
    var statusLabel: String = "Waiting for the phone runtime."
    var bluetoothClientCount: Int = 0
    var notificationAccessEnabled: Bool = false
    var lastError: String? = nil
}

enum LyricsSessionState: String, Codable {
    case idle = "IDLE"
    case loading = "LOADING"
    case ready = "READY"
    case playing = "PLAYING"
    case error = "ERROR"
}

struct LyricsLine: Codable, Equatable {
    var startTimeMs: Int64 = 0
    var text: String = ""
}

struct LyricsSnapshot: Codable {
    var sessionState: LyricsSessionState = .idle
    var trackTitle: String = ""
    var artistName: String = ""
    var albumName: String = ""
    var durationSeconds: Int? = nil
    var provider: String = ""
    var sourceSummary: String = "Waiting for active media playback on the phone."
    var synced: Bool = false
    var progressMs: Int64 = 0
    var capturedAtEpochMs: Int64 = 0
    var currentLineIndex: Int = -1
    var lines: [LyricsLine] = []
    var plainLyrics: String = ""
    var errorMessage: String? = nil
}

struct LyricsPlaybackSync: Codable {
    var sessionState: LyricsSessionState = .idle
    var progressMs: Int64 = 0
    var capturedAtEpochMs: Int64 = 0
    var currentLineIndex: Int = -1
}

struct ProtocolHello: Codable {
    var protocolVersion: Int = 1
    var appVersion: String = ""
    var capabilities: [String] = []
}

struct ProtocolHelloAck: Codable {
    var protocolVersion: Int = 1
    var appVersion: String = ""
    var capabilities: [String] = []
}

enum GlassesToPhoneMessage {
    case hello(ProtocolHello)
    case requestSnapshot
    case requestStatus
    case togglePlayback
}

enum LyricsEvent {
    case snapshot(LyricsSnapshot)
    case sync(LyricsPlaybackSync)
    case error(String)
}

enum PhoneToGlassesMessage {
    case helloAck(ProtocolHelloAck)
    case status(DeviceStatus)
    case lyrics(LyricsEvent)
    case error(String)
}
