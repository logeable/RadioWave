import SwiftUI
import AppKit

struct StationArtworkView: View {
    var image: Image? = nil
    var size: CGFloat = 48
    var symbol = "dot.radiowaves.left.and.right"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(LinearGradient(
                    colors: [RadioUIStyle.accent.opacity(0.22), RadioUIStyle.accent.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            if let image {
                image
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
    }
}
