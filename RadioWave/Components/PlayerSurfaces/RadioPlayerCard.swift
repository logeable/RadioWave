import SwiftUI

struct RadioPlayerCard: View {
    let station: RadioStationInfo
    var status: RadioPlaybackStatus = .live
    var isFavorite = false
    var isPlaying = true
    @Binding var volume: Double
    var onPlayPause: () -> Void = {}
    var onFavorite: () -> Void = {}
    var onStations: () -> Void = {}
    var onMini: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                RadioIconButton(systemName: "list.bullet", label: "打开电台列表", action: onStations)
            }
            StationArtworkView(image: station.artwork, size: 188)
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
            StationMetadataView(station: station, alignment: .center)
            PlaybackStatusView(status: status)
            PlayPauseButton(isPlaying: isPlaying, action: onPlayPause)
            HStack(spacing: 13) {
                FavoriteButton(isFavorite: isFavorite, action: onFavorite)
                VolumeControl(volume: $volume)
                RadioIconButton(systemName: "rectangle.compress.vertical", label: "迷你播放器", action: onMini)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 360)
        .background(RadioUIStyle.canvas, in: RoundedRectangle(cornerRadius: RadioUIStyle.cornerLarge))
        .overlay(RoundedRectangle(cornerRadius: RadioUIStyle.cornerLarge).stroke(RadioUIStyle.separator))
    }
}
