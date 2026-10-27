import SwiftUI

struct StationRowView: View {
    let station: RadioStationInfo
    var status: RadioPlaybackStatus? = nil
    var isFavorite = false
    var isCurrent = false
    var isPlaying = false
    var onPlay: () -> Void = {}
    var onFavorite: () -> Void = {}

    var body: some View {
        HStack(spacing: 11) {
            StationArtworkView(image: station.artwork, imageURL: station.artworkURL, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(station.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let status, isCurrent { PlaybackStatusView(status: status, compact: true) }
                }
                Text(station.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            FavoriteButton(isFavorite: isFavorite, size: 30, action: onFavorite)
            RadioIconButton(
                systemName: isCurrent && isPlaying ? "pause.fill" : "play.fill",
                label: isCurrent && isPlaying ? "暂停" : "播放",
                isSelected: isCurrent,
                size: 30,
                action: onPlay
            )
        }
        .padding(9)
        .background(
            .ultraThinMaterial.opacity(isCurrent ? 0.38 : 0.24),
            in: RoundedRectangle(cornerRadius: RadioUIStyle.cornerMedium)
        )
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: RadioUIStyle.cornerMedium)
                    .fill(RadioUIStyle.accent.opacity(0.07))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: RadioUIStyle.cornerMedium))
        .accessibilityElement(children: .contain)
    }
}
