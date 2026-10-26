import SwiftUI

struct RadioPlayerScreen: View {
    @ObservedObject var player: RadioPlayerViewModel
    @ObservedObject var library: RadioLibraryViewModel
    let onShowStations: () -> Void

    private var stationInfo: RadioStationInfo? {
        player.currentStation.map(RadioStationInfo.init(station:))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 24)

            if let station = player.currentStation, let stationInfo {
                playerContent(station: station, info: stationInfo)
            } else {
                noStationContent
            }

            Spacer(minLength: 28)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadioUIStyle.canvas)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RadioUIStyle.accent)
            Text("Radio")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            RadioIconButton(systemName: "list.bullet", label: "打开电台列表", action: onShowStations)
        }
    }

    private func playerContent(station: Station, info: RadioStationInfo) -> some View {
        VStack(spacing: 13) {
            StationArtworkView(imageURL: info.artworkURL, size: 188)
                .shadow(color: .black.opacity(0.13), radius: 20, y: 9)

            StationMetadataView(station: info, alignment: .center)

            PlaybackStatusView(status: player.playbackStatus)

            if let title = player.nowPlayingTitle, !title.isEmpty {
                Label(title, systemImage: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }

            if let playbackError = player.playbackError {
                Text(playbackError)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            PlayPauseButton(
                isPlaying: player.isPlaying,
                isConnecting: player.isConnecting,
                isEnabled: !player.isConnecting,
                size: 66,
                action: player.togglePlayback
            )
            .padding(.top, 2)

            HStack(spacing: 16) {
                FavoriteButton(
                    isFavorite: library.isFavorite(station),
                    action: { library.toggleFavorite(station) }
                )
                VolumeControl(volume: $player.volume)
                    .frame(maxWidth: 190)
            }
            .padding(.top, 5)

            if player.playbackError != nil {
                Button("重试") { player.play(station) }
                    .buttonStyle(.bordered)
                    .tint(RadioUIStyle.accent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var noStationContent: some View {
        VStack(spacing: 18) {
            StationArtworkView(size: 150)
                .opacity(0.75)
            RadioEmptyStateView(
                symbol: "dot.radiowaves.left.and.right",
                title: "准备好收听了吗？",
                detail: "浏览电台，找到适合此刻的声音。",
                actionTitle: "浏览电台",
                action: onShowStations
            )
            .frame(maxWidth: 320)
        }
    }
}
