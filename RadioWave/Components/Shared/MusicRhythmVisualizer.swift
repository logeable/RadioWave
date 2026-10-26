import SwiftUI

struct MusicRhythmVisualizer: View {
    let audioBands: AudioBandLevels
    var isActive = true

    private enum FrequencyBand {
        case bass
        case mid
        case treble
    }

    private struct Bar {
        let band: FrequencyBand
        let strength: CGFloat
    }

    private let bars: [Bar] = [
        Bar(band: .treble, strength: 0.34),
        Bar(band: .treble, strength: 0.48),
        Bar(band: .mid, strength: 0.66),
        Bar(band: .mid, strength: 0.84),
        Bar(band: .bass, strength: 1),
        Bar(band: .mid, strength: 0.84),
        Bar(band: .mid, strength: 0.66),
        Bar(band: .treble, strength: 0.48),
        Bar(band: .treble, strength: 0.34)
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(bars.indices, id: \.self) { index in
                let bar = bars[index]
                Capsule()
                    .fill(RadioUIStyle.accent.opacity(isActive ? 0.9 : 0.22))
                    .frame(width: 3.5, height: barHeight(for: bar))
                    .shadow(color: RadioUIStyle.accent.opacity(isActive ? 0.25 : 0), radius: 3)
            }
        }
        .frame(height: 126)
        .animation(.easeOut(duration: 0.07), value: audioBands)
        .accessibilityHidden(true)
    }

    private func barHeight(for bar: Bar) -> CGFloat {
        let level: Double
        switch bar.band {
        case .bass:
            level = audioBands.bass
        case .mid:
            level = audioBands.mid
        case .treble:
            level = audioBands.treble
        }

        return 5 + 92 * CGFloat(min(max(level, 0), 1)) * bar.strength
    }
}
