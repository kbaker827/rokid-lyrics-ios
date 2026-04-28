import Foundation

private struct WireEnvelope: Codable {
    let channel: String
    let type: String
    let payloadJson: String?
}

enum WireProtocol {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Encode

    static func encodePhoneMessage(_ message: PhoneToGlassesMessage) -> String? {
        guard let envelope = phoneEnvelopeFor(message),
              let data = try? encoder.encode(envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Decode

    static func decodeGlassesMessage(_ json: String) -> GlassesToPhoneMessage? {
        guard let data = json.data(using: .utf8),
              let envelope = try? decoder.decode(WireEnvelope.self, from: data) else { return nil }
        return glassesMessageFor(envelope)
    }

    // MARK: - Phone → Wire

    private static func phoneEnvelopeFor(_ message: PhoneToGlassesMessage) -> WireEnvelope? {
        switch message {
        case .helloAck(let ack):
            return WireEnvelope(channel: "runtime", type: "hello_ack", payloadJson: encodePayload(ack))
        case .status(let status):
            return WireEnvelope(channel: "runtime", type: "status", payloadJson: encodePayload(status))
        case .lyrics(let event):
            switch event {
            case .snapshot(let snapshot):
                return WireEnvelope(channel: "lyrics", type: "snapshot", payloadJson: encodePayload(snapshot))
            case .sync(let sync):
                return WireEnvelope(channel: "lyrics", type: "sync", payloadJson: encodePayload(sync))
            case .error(let message):
                struct LyricsErrorPayload: Codable { let message: String }
                return WireEnvelope(channel: "lyrics", type: "error", payloadJson: encodePayload(LyricsErrorPayload(message: message)))
            }
        case .error(let message):
            struct RuntimeErrorPayload: Codable { let message: String }
            return WireEnvelope(channel: "runtime", type: "error", payloadJson: encodePayload(RuntimeErrorPayload(message: message)))
        }
    }

    // MARK: - Wire → Glasses

    private static func glassesMessageFor(_ envelope: WireEnvelope) -> GlassesToPhoneMessage? {
        switch envelope.channel {
        case "runtime":
            switch envelope.type {
            case "hello":
                return parsePayload(envelope, ProtocolHello.self).map { .hello($0) }
            case "request_snapshot":
                return .requestSnapshot
            case "request_status":
                return .requestStatus
            case "toggle_playback":
                return .togglePlayback
            default:
                return nil
            }
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private static func encodePayload<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parsePayload<T: Decodable>(_ envelope: WireEnvelope, _ type: T.Type) -> T? {
        guard let json = envelope.payloadJson,
              let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
