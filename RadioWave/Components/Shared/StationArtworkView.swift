import SwiftUI
import AppKit

struct StationArtworkView: View {
    var image: Image? = nil
    var imageURL: URL? = nil
    var size: CGFloat = 48
    var symbol = "dot.radiowaves.left.and.right"

    @State private var loadedImage: NSImage?

    private var displayedImage: Image? {
        if let image { return image }
        if let loadedImage { return Image(nsImage: loadedImage) }
        return nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(LinearGradient(
                    colors: [RadioUIStyle.accent.opacity(0.22), RadioUIStyle.accent.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            if let displayedImage {
                displayedImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(RadioUIStyle.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("电台封面")
        .task(id: imageURL) {
            loadedImage = nil
            guard let imageURL,
                  let data = await StationIconCache.shared.data(for: imageURL) else { return }
            loadedImage = NSImage(data: data)
        }
    }
}
