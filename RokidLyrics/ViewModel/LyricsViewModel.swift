import Foundation
import Combine

@MainActor
final class LyricsViewModel: ObservableObject {
    @Published private(set) var lyricsSnapshot: LyricsSnapshot = LyricsSnapshot()
    @Published private(set) var deviceStatus: DeviceStatus = DeviceStatus()
    @Published private(set) var statusMessage: String = "Starting up…"
    @Published private(set) var glassesConnectionState: ConnectionState = .disconnected
    @Published private(set) var glassesClientCount: Int = 0

    let glassesServer = GlassesServer()
    private let nowPlayingMonitor = NowPlayingMonitor()
    private let lyricsEngine = LyricsRuntimeEngine()
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Timer?

    func start() {
        setupObservers()
        nowPlayingMonitor.start()
        glassesServer.start()
        glassesServer.onMessage = { [weak self] msg in
            Task { @MainActor in self?.handleGlassesMessage(msg) }
        }
        glassesServer.onStatusChanged = { [weak self] msg in
            Task { @MainActor in self?.statusMessage = msg }
        }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        nowPlayingMonitor.stop()
        glassesServer.stop()
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Private

    private func setupObservers() {
        nowPlayingMonitor.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] media in
                Task { @MainActor in
                    self?.lyricsEngine.update(media: media)
                }
            }
            .store(in: &cancellables)

        lyricsEngine.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                self?.lyricsSnapshot = snap
                self?.broadcastSnapshot(snap)
            }
            .store(in: &cancellables)

        glassesServer.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.glassesConnectionState = state
                self?.updateDeviceStatus()
            }
            .store(in: &cancellables)

        glassesServer.$clientCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.glassesClientCount = count
                self?.updateDeviceStatus()
            }
            .store(in: &cancellables)
    }

    private func tick() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sync = lyricsEngine.syncSnapshot(capturedAt: nowMs)
        let msg = PhoneToGlassesMessage.lyrics(.sync(sync))
        glassesServer.broadcastDebounced(msg)
    }

    private func broadcastSnapshot(_ snap: LyricsSnapshot) {
        glassesServer.broadcast(.lyrics(.snapshot(snap)))
    }

    private func handleGlassesMessage(_ msg: GlassesToPhoneMessage) {
        switch msg {
        case .requestSnapshot:
            glassesServer.broadcast(.lyrics(.snapshot(lyricsSnapshot)))
        case .requestStatus:
            glassesServer.broadcast(.status(deviceStatus))
        case .togglePlayback:
            nowPlayingMonitor.togglePlayback()
        case .hello:
            break // handled by server
        }
    }

    private func updateDeviceStatus() {
        deviceStatus = DeviceStatus(
            connectionState: glassesConnectionState,
            statusLabel: statusMessage,
            bluetoothClientCount: glassesClientCount,
            notificationAccessEnabled: true
        )
        glassesServer.broadcast(.status(deviceStatus))
    }
}
