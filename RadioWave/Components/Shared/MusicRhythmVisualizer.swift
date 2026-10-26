import SwiftUI

struct MusicRhythmVisualizer: View {
    let audioLevel: Double
    var isActive = true

    private let barStrengths: [CGFloat] = [0.28, 0.42, 0.62, 0.82, 1, 0.72, 0.48, 0.34]

    var body: some View {
        HStack(spacing: 4) {
            bars
        }
        .frame(height: 126)
        .animation(.easeOut(duration: 0.07), value: audioLevel)
        .accessibilityHidden(true)
    }

    private var bars: some View {
        HStack(spacing: 3) {
            ForEach(barStrengths.indices, id: \.self) { index in
                Capsule()
                    .fill(RadioUIStyle.accent.opacity(isActive ? 0.9 : 0.22))
                    .frame(width: 3.5, height: barHeight(for: barStrengths[index]))
                    .shadow(color: RadioUIStyle.accent.opacity(isActive ? 0.25 : 0), radius: 3)
            }
        }
        .frame(height: 126)
    }

    private func barHeight(for strength: CGFloat) -> CGFloat {
        let normalizedLevel = min(max(audioLevel, 0), 1)
        return 5 + 92 * CGFloat(normalizedLevel) * strength
    }
}
