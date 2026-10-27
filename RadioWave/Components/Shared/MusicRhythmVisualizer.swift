import AppKit
import SwiftUI

struct MusicRhythmVisualizer: View {
    let audioBands: AudioBandLevels
    let backgroundImage: NSImage?
    var isActive = true

    @State private var colorPalette = [RadioUIStyle.accent, RadioUIStyle.accent, RadioUIStyle.accent]

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
                    .fill(color(for: bar).opacity(isActive ? 0.92 : 0.22))
                    .frame(width: 3.5, height: barHeight(for: bar))
                    .shadow(color: color(for: bar).opacity(isActive ? 0.28 : 0), radius: 3)
            }
        }
        .frame(height: 126)
        .animation(.easeOut(duration: 0.07), value: audioBands)
        .onAppear(perform: updateColorPalette)
        .onChange(of: backgroundImage.map { ObjectIdentifier($0) }) { _, _ in
            updateColorPalette()
        }
        .accessibilityHidden(true)
    }

    private func color(for bar: Bar) -> Color {
        let index: Int
        switch bar.band {
        case .bass: index = 0
        case .mid: index = 1
        case .treble: index = 2
        }
        return colorPalette[index]
    }

    private func updateColorPalette() {
        let newPalette = backgroundImage.map(Self.colors(from:)) ?? Self.fallbackPalette
        withAnimation(.easeInOut(duration: 0.8)) {
            colorPalette = newPalette
        }
    }

    private static let fallbackPalette = [
        RadioUIStyle.accent,
        RadioUIStyle.accent.opacity(0.86),
        RadioUIStyle.accent.opacity(0.72)
    ]

    private static func colors(from image: NSImage) -> [Color] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallbackPalette
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let binCount = 12
        var hueWeights = Array(repeating: 0.0, count: binCount)
        var hueTotals = Array(repeating: 0.0, count: binCount)
        var saturationTotals = Array(repeating: 0.0, count: binCount)
        let xStep = max(1, bitmap.pixelsWide / 28)
        let yStep = max(1, bitmap.pixelsHigh / 28)

        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                guard saturation > 0.20, brightness > 0.10, brightness < 0.94, alpha > 0.1 else { continue }

                let index = min(binCount - 1, Int(hue * CGFloat(binCount)))
                let weight = Double(saturation)
                hueWeights[index] += weight
                hueTotals[index] += Double(hue) * weight
                saturationTotals[index] += Double(saturation) * weight
            }
        }

        let dominantBins = (0..<binCount)
            .filter { hueWeights[$0] > 0 }
            .sorted { hueWeights[$0] > hueWeights[$1] }
            .prefix(3)

        let extracted = dominantBins.map { index -> Color in
            let hue = CGFloat(hueTotals[index] / hueWeights[index])
            let saturation = CGFloat(saturationTotals[index] / hueWeights[index])
            return Color(
                hue: hue,
                saturation: min(0.86, max(0.48, saturation)),
                brightness: 0.82
            )
        }
        guard let first = extracted.first else { return fallbackPalette }
        if extracted.count == 1 {
            let primaryIndex = (0..<binCount).first { hueWeights[$0] > 0 } ?? 0
            let primaryHue = CGFloat(hueTotals[primaryIndex] / hueWeights[primaryIndex])
            return [
                first,
                Color(hue: primaryHue,
                      saturation: 0.60,
                      brightness: 0.68),
                Color(hue: primaryHue,
                      saturation: 0.40,
                      brightness: 0.92)
            ]
        }
        if extracted.count == 2 { return [extracted[0], extracted[1], extracted[0].opacity(0.76)] }
        return extracted
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
