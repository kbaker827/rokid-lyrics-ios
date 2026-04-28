import Foundation
import Network

@MainActor
final class GlassesServer: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var glassesAppVersion: String = ""
    @Published private(set) var clientCount: Int = 0

    var onMessage: ((GlassesToPhoneMessage) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
    private let port: NWEndpoint.Port = 8081
    private let broadcastDebouncer = Debouncer(delay: 0.1)

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: port)
        } catch {
            onStatusChanged?("Failed to create listener: \(error.localizedDescription)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleListenerState(state) }
        }
        listener?.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.acceptConnection(conn) }
        }
        listener?.start(queue: .main)
        onStatusChanged?("Wi-Fi server listening on port \(port). Connect glasses to \(localIPAddress() ?? "your phone IP"):\(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        receiveBuffers.removeAll()
        clientCount = 0
        connectionState = .disconnected
    }

    func broadcast(_ message: PhoneToGlassesMessage) {
        guard let json = WireProtocol.encodePhoneMessage(message) else { return }
        let frame = (json + "\n").data(using: .utf8)!
        for conn in connections {
            conn.send(content: frame, completion: .idempotent)
        }
    }

    func broadcastDebounced(_ message: PhoneToGlassesMessage) {
        broadcastDebouncer.schedule { [weak self] in
            Task { @MainActor in self?.broadcast(message) }
        }
    }

    var localIP: String? { localIPAddress() }

    // MARK: - Listener state

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            connectionState = connections.isEmpty ? .disconnected : .connected
        case .failed(let err):
            onStatusChanged?("Listener failed: \(err.localizedDescription)")
            connectionState = .disconnected
            listener = nil
        default:
            break
        }
    }

    // MARK: - Connection handling

    private func acceptConnection(_ conn: NWConnection) {
        connections.append(conn)
        receiveBuffers[ObjectIdentifier(conn)] = Data()
        clientCount = connections.count
        connectionState = .connected

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleConnectionState(conn, state: state) }
        }
        conn.start(queue: .main)
        receiveNext(conn)
    }

    private func handleConnectionState(_ conn: NWConnection, state: NWConnection.State) {
        switch state {
        case .cancelled, .failed:
            removeConnection(conn)
        default:
            break
        }
    }

    private func removeConnection(_ conn: NWConnection) {
        connections.removeAll { $0 === conn }
        receiveBuffers.removeValue(forKey: ObjectIdentifier(conn))
        clientCount = connections.count
        if connections.isEmpty { connectionState = .disconnected }
    }

    private func receiveNext(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffers[ObjectIdentifier(conn), default: Data()].append(data)
                    self.processBuffer(conn)
                }
                if isComplete || error != nil {
                    self.removeConnection(conn)
                } else {
                    self.receiveNext(conn)
                }
            }
        }
    }

    private func processBuffer(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        guard var buf = receiveBuffers[key] else { return }
        while let newlineIdx = buf.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buf.prefix(upTo: newlineIdx)
            buf = buf.suffix(from: buf.index(after: newlineIdx))
            if let json = String(data: lineData, encoding: .utf8) {
                handleIncoming(json: json, conn: conn)
            }
        }
        receiveBuffers[key] = buf
    }

    private func handleIncoming(json: String, conn: NWConnection) {
        guard let msg = WireProtocol.decodeGlassesMessage(json) else { return }
        switch msg {
        case .hello(let hello):
            glassesAppVersion = hello.appVersion
            let ack = ProtocolHelloAck(protocolVersion: 1, appVersion: appVersion(), capabilities: [])
            sendTo(conn, message: .helloAck(ack))
        default:
            onMessage?(msg)
        }
    }

    private func sendTo(_ conn: NWConnection, message: PhoneToGlassesMessage) {
        guard let json = WireProtocol.encodePhoneMessage(message) else { return }
        let frame = (json + "\n").data(using: .utf8)!
        conn.send(content: frame, completion: .idempotent)
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            let addr = current.pointee
            if addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: addr.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    return String(cString: hostname)
                }
            }
            ptr = addr.ifa_next
        }
        return nil
    }
}

// MARK: - Debouncer

final class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?

    init(delay: TimeInterval) { self.delay = delay }

    func schedule(_ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
