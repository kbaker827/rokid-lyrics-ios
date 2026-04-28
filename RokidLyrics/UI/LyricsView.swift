import SwiftUI

struct LyricsView: View {
    let snapshot: LyricsSnapshot

    private var lines: [LyricsLine] { snapshot.lines }
    private var currentIndex: Int { snapshot.currentLineIndex }

    var body: some View {
        VStack(spacing: 0) {
            if snapshot.sessionState == .loading {
                loadingView
            } else if snapshot.sessionState == .error {
                errorView
            } else if lines.isEmpty {
                plainLyricsView
            } else {
                syncedLyricsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Synced lyrics (scrolling display)

    private var syncedLyricsView: some View {
        VStack(spacing: 8) {
            // Past line
            LyricsLineView(
                text: safeText(at: currentIndex - 1),
                role: .past,
                isPlaying: snapshot.sessionState == .playing
            )

            // Current line (highlighted)
            LyricsLineView(
                text: safeText(at: currentIndex),
                role: .current,
                isPlaying: snapshot.sessionState == .playing
            )
            .padding(.vertical, 8)

            // Next lines
            LyricsLineView(
                text: safeText(at: currentIndex + 1),
                role: .next1,
                isPlaying: snapshot.sessionState == .playing
            )
            LyricsLineView(
                text: safeText(at: currentIndex + 2),
                role: .next2,
                isPlaying: snapshot.sessionState == .playing
            )
        }
        .padding(.vertical, 24)
    }

    // MARK: - Plain lyrics

    private var plainLyricsView: some View {
        ScrollView {
            Text(snapshot.plainLyrics.isEmpty ? snapshot.sourceSummary : snapshot.plainLyrics)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(24)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Looking up lyrics…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var errorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(snapshot.errorMessage ?? "Lyrics not found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func safeText(at index: Int) -> String {
        guard index >= 0, index < lines.count else { return "" }
        return lines[index].text
    }
}
