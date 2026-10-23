import SwiftUI
import AppKit

struct StationArtwork: View {
    let station: Station
    var size: CGFloat = 46

    @State private var faviconImage: NSImage?

    private var cornerRadius: CGFloat { size > 48 ? 13 : 10 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(colors: [RadioPalette.accent.opacity(0.18), Color(red: 0.96, green: 0.78, blue: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "waveform")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(RadioPalette.accent)
        }
        .overlay {
            if let faviconImage {
                Image(nsImage: faviconImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .frame(width: size, height: size)
        .task(id: station.favicon) {
            faviconImage = nil
            guard let favicon = station.favicon,
                  let url = URL(string: favicon) else { return }
            guard let data = await StationIconCache.shared.data(for: url) else { return }
            faviconImage = NSImage(data: data)
        }
    }
}
