import SwiftUI

struct VolumeControl: View {
    @Binding var volume: Double
    var compact = false
    @State private var lastAudibleVolume = 0.65

    private var isMuted: Bool { volume <= 0.001 }

    var body: some View {
        HStack(spacing: 8) {
            RadioIconButton(
                systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: isMuted ? "取消静音" : "静音",
                isSelected: isMuted,
                size: compact ? 28 : 32
            ) {
                if isMuted {
                    volume = lastAudibleVolume
                } else {
                    lastAudibleVolume = volume
                    volume = 0
                }
            }
            Slider(value: $volume, in: 0...1)
                .tint(RadioUIStyle.accent)
                .frame(minWidth: compact ? 72 : 100, idealWidth: compact ? 92 : 140)
                .accessibilityLabel("音量")
                .onChange(of: volume) { _, newValue in
                    if newValue > 0.001 { lastAudibleVolume = newValue }
                }
        }
    }
}
