import SwiftUI

struct RadioPlayerScreen: View {
    @ObservedObject var player: RadioPlayerViewModel
    @ObservedObject var library: RadioLibraryViewModel
    let onShowStations: () -> Void
    @Environment(\.openSettings) private var openSettings

    private var stationInfo: RadioStationInfo? {
        player.currentStation.map(RadioStationInfo.init(station:))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 24)

            playerSurface

            Spacer(minLength: 28)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    @ViewBuilder
    private var playerSurface: some View {
        Group {
            if let station = player.currentStation, let stationInfo {
                playerContent(station: station, info: stationInfo)
            } else {
                noStationContent
            }
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.24))
                .mask {
                    RadialGradient(
                        stops: [
                            .init(color: .black.opacity(0.72), location: 0),
                            .init(color: .black.opacity(0.54), location: 0.58),
                            .init(color: .black.opacity(0.20), location: 0.86),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        startRadius: 72,
                        endRadius: 330
                    )
                }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Spacer()
            if library.isChoosingRandomStation {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34, height: 34)
                    .help("正在准备随机电台")
            } else {
                RadioIconButton(
                    systemName: "shuffle",
                    label: "随机播放电台",
                    action: playRandomStation
                )
            }
            RadioIconButton(systemName: "list.bullet", label: "打开电台列表", action: onShowStations)
            RadioIconButton(systemName: "gearshape", label: "打开设置", action: { openSettings() })
        }
    }

    private func playRandomStation() {
        library.requestRandomStation(excluding: player.currentStation?.id) { station in
            guard let station else { return }
            player.play(station)
        }
    }

    private func playerContent(station: Station, info: RadioStationInfo) -> some View {
        VStack(spacing: 13) {
            HStack(spacing: 14) {
                MusicRhythmVisualizer(
                    audioBands: player.audioBands,
                    backgroundImage: player.generatedBackgroundImage,
                    isActive: player.isPlaying
                )
                StationArtworkView(imageURL: info.artworkURL, size: 188)
                    .shadow(color: .black.opacity(0.13), radius: 20, y: 9)
                MusicRhythmVisualizer(
                    audioBands: player.audioBands,
                    backgroundImage: player.generatedBackgroundImage,
                    isActive: player.isPlaying
                )
                    .scaleEffect(x: -1, y: 1)
            }

            VStack(spacing: 5) {
                StationMetadataView(
                    station: info,
                    alignment: .center,
                    detailColor: Color.primary.opacity(0.82)
                )

                if let title = player.nowPlayingTitle, !title.isEmpty {
                    Label(title, systemImage: "music.note")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
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
