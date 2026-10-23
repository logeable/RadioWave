import SwiftUI

struct StationArtwork: View {
    let station: Station
    var size: CGFloat = 46

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
            if let favicon = station.favicon, let url = URL(string: favicon), url.scheme == "https" {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    EmptyView()
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .frame(width: size, height: size)
    }
}
