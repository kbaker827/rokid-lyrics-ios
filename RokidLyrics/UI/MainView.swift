import SwiftUI

struct MainView: View {
    @StateObject private var viewModel = LyricsViewModel()

    var body: some View {
        TabView {
            nowPlayingTab
                .tabItem { Label("Now Playing", systemImage: "music.note") }

            SettingsView(viewModel: viewModel)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Now Playing tab

    private var nowPlayingTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                trackHeader
                Divider()
                LyricsView(snapshot: viewModel.lyricsSnapshot)
                Divider()
                statusBar
            }
            .navigationTitle("Rokid Lyrics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var trackHeader: some View {
        VStack(spacing: 4) {
            let snap = viewModel.lyricsSnapshot
            let title = snap.trackTitle.isEmpty ? "No track playing" : snap.trackTitle
            let subtitle = [snap.artistName, snap.albumName].filter { !$0.isEmpty }.joined(separator: " · ")

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .padding(.top, 12)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !snap.provider.isEmpty {
                Text(snap.provider)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(viewModel.glassesClientCount > 0
                 ? "\(viewModel.glassesClientCount) glasses connected"
                 : "Waiting for glasses on port 8081")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            sessionStateLabel
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var connectionColor: Color {
        viewModel.glassesConnectionState == .connected ? .green : .orange
    }

    private var sessionStateLabel: some View {
        let state = viewModel.lyricsSnapshot.sessionState
        let (label, color): (String, Color) = switch state {
        case .idle:    ("Idle", .secondary)
        case .loading: ("Loading", .orange)
        case .ready:   ("Ready", .blue)
        case .playing: ("Playing", .green)
        case .error:   ("Error", .red)
        }
        return Text(label)
            .font(.caption.bold())
            .foregroundStyle(color)
    }
}
