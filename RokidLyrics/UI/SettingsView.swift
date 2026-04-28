import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: LyricsViewModel

    var body: some View {
        NavigationStack {
            Form {
                glassesSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Glasses

    private var glassesSection: some View {
        Section("Glasses Connection") {
            HStack {
                Label("Phone IP", systemImage: "wifi")
                Spacer()
                Text(viewModel.glassesServer.localIP ?? "Not available")
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            HStack {
                Label("Port", systemImage: "network")
                Spacer()
                Text("8081")
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            HStack {
                Label("Connected Glasses", systemImage: "applewatch")
                Spacer()
                Text("\(viewModel.glassesClientCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Status", systemImage: stateIcon)
                Spacer()
                Text(stateLabel)
                    .foregroundStyle(stateColor)
            }
        } footer: {
            Text("On your Rokid glasses, open the Lyrics app and point it to \(viewModel.glassesServer.localIP ?? "your phone IP"):8081 using Wi-Fi mode.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            Link("Original Android Project", destination: URL(string: "https://github.com/Anezium/awesome-rokid")!)
        }
    }

    private var stateIcon: String {
        switch viewModel.glassesConnectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.clockwise"
        case .disconnected: return "xmark.circle"
        }
    }

    private var stateLabel: String {
        switch viewModel.glassesConnectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Waiting"
        }
    }

    private var stateColor: Color {
        switch viewModel.glassesConnectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        }
    }
}
