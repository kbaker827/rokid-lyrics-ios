import SwiftUI

struct LyricsLineView: View {
    let text: String
    let role: LineRole
    let isPlaying: Bool

    enum LineRole {
        case past, current, next1, next2
    }

    var body: some View {
        Text(text.isEmpty ? "♪" : text)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
            .animation(.easeInOut(duration: 0.25), value: text)
    }

    private var font: Font {
        switch role {
        case .current: return .title2.bold()
        case .next1:   return .body.weight(.medium)
        case .past, .next2: return .subheadline
        }
    }

    private var color: Color {
        switch role {
        case .current: return .primary
        case .next1:   return .secondary
        case .past, .next2: return .secondary.opacity(0.5)
        }
    }
}
