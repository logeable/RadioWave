import SwiftUI

struct RadioComponentsGallery: View {
    @State private var volume = 0.68
    @State private var isFavorite = true
    @State private var isPlaying = true
    @State private var searchText = ""
    @State private var category: RadioStationCategory = .recommended
    @State private var launchAtLogin = false

    private let station = RadioStationInfo(
        id: "nts",
        name: "NTS Radio",
        detail: "Electronic · Experimental · London"
    )
    private let otherStations = [
        RadioStationInfo(id: "kexp", name: "KEXP", detail: "Indie · Alternative · Seattle"),
        RadioStationInfo(id: "soma", name: "SomaFM", detail: "Ambient · Electronic · Global"),
        RadioStationInfo(id: "bbc", name: "BBC Radio 6 Music", detail: "Indie · Rock · UK")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                HStack(alignment: .top, spacing: 24) {
                    section("主播放器") {
                        RadioPlayerCard(
                            station: station,
                            status: .live,
                            isFavorite: isFavorite,
                            isPlaying: isPlaying,
                            volume: $volume,
                            onPlayPause: { isPlaying.toggle() },
                            onFavorite: { isFavorite.toggle() }
                        )
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        section("菜单栏面板") {
                            MenuBarPlayerCard(station: station, isPlaying: isPlaying, isFavorite: isFavorite, volume: $volume,
                                              onPlayPause: { isPlaying.toggle() },
                                              onFavorite: { isFavorite.toggle() })
                        }
                    }
                }
                section("电台列表组件") {
                    VStack(spacing: 8) {
                        StationSearchField(text: $searchText)
                        StationCategoryPicker(selection: $category)
                        StationRowView(station: station, status: .live, isFavorite: isFavorite,
                                       isCurrent: true, isPlaying: isPlaying,
                                       onPlay: { isPlaying.toggle() },
                                       onFavorite: { isFavorite.toggle() })
                        ForEach(otherStations) { item in
                            StationRowView(station: item, onPlay: {}, onFavorite: {})
                        }
                    }
                    .padding(14)
                    .background(RadioUIStyle.canvas, in: RoundedRectangle(cornerRadius: RadioUIStyle.cornerLarge))
                    .frame(maxWidth: 520)
                }
                HStack(alignment: .top, spacing: 24) {
                    section("播放状态") {
                        VStack(alignment: .leading, spacing: 12) {
                            PlaybackStatusView(status: .connecting)
                            PlaybackStatusView(status: .live)
                            PlaybackStatusView(status: .paused)
                            PlaybackStatusView(status: .failed)
                        }
                        .padding(18)
                        .background(RadioUIStyle.canvas, in: RoundedRectangle(cornerRadius: RadioUIStyle.cornerMedium))
                    }
                    section("设置与空状态") {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingToggleRow(title: "开机启动", detail: "默认关闭", isOn: $launchAtLogin)
                            Divider()
                            RadioEmptyStateView(symbol: "heart", title: "还没有收藏电台", detail: "点击电台旁的心形即可收藏。", actionTitle: "去发现电台")
                        }
                        .padding(16)
                        .frame(width: 340)
                        .background(RadioUIStyle.canvas, in: RoundedRectangle(cornerRadius: RadioUIStyle.cornerMedium))
                    }
                }
            }
            .padding(28)
        }
        .frame(minWidth: 1100, minHeight: 1000)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Radio · UI Components")
                .font(.system(size: 24, weight: .bold))
            Text("共享播放组件与界面组合预览 · 外观跟随 macOS")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
    }
}

#Preview("Radio Components") {
    RadioComponentsGallery()
}
