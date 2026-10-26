import AppKit
import SwiftUI

struct RadioMenuBarView: View {
    @ObservedObject var player: RadioPlayerViewModel
    @ObservedObject var library: RadioLibraryViewModel
    @ObservedObject var navigation: RadioNavigationModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            if let station = player.currentStation {
                MenuBarPlayerCard(
                    station: RadioStationInfo(station: station),
                    isPlaying: player.isPlaying,
                    playbackStatus: player.playbackStatus,
                    isConnecting: player.isConnecting,
                    isFavorite: library.isFavorite(station),
                    volume: $player.volume,
                    onPlayPause: player.togglePlayback,
                    onFavorite: { library.toggleFavorite(station) },
                    onOpenSettings: { openSettings() }
                )
            } else {
                RadioEmptyStateView(
                    symbol: "dot.radiowaves.left.and.right",
                    title: "还没有正在收听的电台",
                    detail: "打开主窗口，从电台列表选择一个电台开始收听。",
                    actionTitle: "打开主窗口",
                    action: showPlayer
                )
                .padding(18)
                .frame(width: 310)
            }

            HStack {
                Button("打开主窗口", action: showPlayer)
                Spacer()
                Button("退出 Radio") { NSApplication.shared.terminate(nil) }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
        }
        .padding(10)
    }

    private func showPlayer() {
        navigation.showingStations = false
        openWindow(id: "main")
    }
}
