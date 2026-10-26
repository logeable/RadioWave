import SwiftUI

struct MenuBarPlayerCard: View {
    let station: RadioStationInfo
    var isPlaying = true
    var playbackStatus: RadioPlaybackStatus = .live
    var isConnecting = false
    var isFavorite = false
    @Binding var volume: Double
    var onPlayPause: () -> Void = {}
    var onFavorite: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StationArtworkView(image: station.artwork, imageURL: station.artworkURL, size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    StationMetadataView(station: station, compact: true)
                    PlaybackStatusView(status: playbackStatus, compact: true)
                }
                Spacer()
                PlayPauseButton(isPlaying: isPlaying, isConnecting: isConnecting, size: 36, action: onPlayPause)
            }
            VolumeControl(volume: $volume)
            Divider()
            HStack {
                FavoriteButton(isFavorite: isFavorite, size: 30, action: onFavorite)
                Text("收藏当前电台").font(.system(size: 12))
                Spacer()
                RadioIconButton(systemName: "gearshape", label: "设置", size: 30, action: onOpenSettings)
            }
        }
        .padding(16)
        .frame(width: 310)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: RadioUIStyle.cornerLarge))
        .overlay(RoundedRectangle(cornerRadius: RadioUIStyle.cornerLarge).stroke(RadioUIStyle.separator))
    }
}
