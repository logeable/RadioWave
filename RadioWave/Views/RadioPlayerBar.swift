import SwiftUI

struct RadioPlayerBar: View {
    @ObservedObject var player: RadioPlayerViewModel
    @ObservedObject var library: RadioLibraryViewModel
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let station = player.currentStation {
                StationArtwork(station: station, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        StationNameLabel(name: station.safeName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(RadioPalette.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            library.toggleFavorite(station)
                        } label: {
                            Image(systemName: library.isFavorite(station) ? "heart.fill" : "heart")
                                .font(.system(size: 12))
                                .foregroundStyle(library.isFavorite(station) ? RadioPalette.accent : RadioPalette.muted)
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(library.isFavorite(station) ? "取消收藏" : "收藏当前电台")
                        .accessibilityLabel(library.isFavorite(station) ? "取消收藏当前电台" : "收藏当前电台")
                    }
                    HStack(spacing: 3) {
                        if player.nowPlayingTitle != nil {
                            Image(systemName: "music.note")
                        }
                        Text(player.nowPlayingTitle ?? (player.isPlaying ? "直播中" : "已暂停"))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(RadioPalette.muted)
                    .lineLimit(1)
                }
                .frame(maxWidth: 230, alignment: .leading)
            } else {
                Text("未播放").font(.system(size: 11)).foregroundStyle(RadioPalette.muted)
            }

            Spacer()

            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RadioPalette.ink)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(player.currentStation == nil)
            .opacity(player.currentStation == nil ? 0.4 : 1)

            Button(action: player.toggleMute) {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(player.isMuted ? RadioPalette.accent : RadioPalette.muted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "取消静音" : "静音")
            .accessibilityLabel(player.isMuted ? "取消静音" : "静音")
            Slider(value: $player.volume, in: 0...1).tint(RadioPalette.accent).frame(width: 85)
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(RadioPalette.line).frame(height: 1) }
        .focusable()
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            player.togglePlayback()
            return .handled
        }
        .onAppear {
            DispatchQueue.main.async {
                hasKeyboardFocus = true
            }
        }
    }
}
