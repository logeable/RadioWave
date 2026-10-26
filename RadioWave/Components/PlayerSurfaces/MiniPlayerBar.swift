import SwiftUI

struct MiniPlayerBar: View {
    let station: RadioStationInfo
    var isPlaying = true
    var isFavorite = false
    @Binding var volume: Double
    var onPlayPause: () -> Void = {}
    var onFavorite: () -> Void = {}
    var onExpand: () -> Void = {}
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            StationArtworkView(image: station.artwork, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(station.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                PlaybackStatusView(status: isPlaying ? .live : .paused, compact: true)
            }
            Spacer(minLength: 6)
            if isHovering {
                FavoriteButton(isFavorite: isFavorite, size: 30, action: onFavorite)
                VolumeControl(volume: $volume, compact: true)
                    .frame(width: 116)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            PlayPauseButton(isPlaying: isPlaying, size: 34, action: onPlayPause)
            RadioIconButton(systemName: "arrow.up.right.and.arrow.down.left", label: "打开主播放器", size: 30, action: onExpand)
        }
        .padding(10)
        .frame(width: isHovering ? 510 : 250)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: RadioUIStyle.cornerMedium))
        .overlay(RoundedRectangle(cornerRadius: RadioUIStyle.cornerMedium).stroke(RadioUIStyle.separator))
        .contentShape(RoundedRectangle(cornerRadius: RadioUIStyle.cornerMedium))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
    }
}
