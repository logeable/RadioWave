import AppKit
import SwiftUI

struct StationRow: View {
    let station: Station
    let isFavorite: Bool
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            StationArtwork(station: station, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                StationNameLabel(name: station.safeName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RadioPalette.ink)
                    .lineLimit(1)
                Text(station.fallbackDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(RadioPalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .foregroundStyle(isFavorite ? RadioPalette.accent : RadioPalette.muted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "取消收藏" : "收藏")

            Button(action: onPlay) {
                Image(systemName: isCurrent && isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCurrent ? RadioPalette.accent : RadioPalette.ink)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isCurrent && isPlaying ? "暂停" : "播放")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

struct StationNameLabel: View {
    let name: String

    var body: some View {
        Text(name)
            .textSelection(.enabled)
            .contextMenu {
                Button("复制电台名", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(name, forType: .string)
                }
            }
    }
}
