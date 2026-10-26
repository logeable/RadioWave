import SwiftUI

struct RadioStationBrowserScreen: View {
    @ObservedObject var library: RadioLibraryViewModel
    @ObservedObject var player: RadioPlayerViewModel
    let onBack: () -> Void
    let onSelectStation: () -> Void

    @State private var searchText = ""
    @State private var category: RadioStationCategory = .recommended

    private var favoriteOnly: Bool { category == .favorites }

    private var visibleStations: [Station] {
        guard category == .recommended else { return library.stations }
        return Array(library.stations.prefix(24))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            StationSearchField(text: $searchText)
                .padding(.top, 12)
            StationCategoryPicker(selection: $category)
                .padding(.top, 12)
                .padding(.bottom, 14)

            stationContent
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadioUIStyle.canvas)
        .onAppear(perform: loadStations)
        .onChange(of: searchText) { _, _ in loadStations() }
        .onChange(of: category) { _, _ in loadStations() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RadioIconButton(systemName: "chevron.left", label: "返回播放器", action: onBack)
            Text("电台列表")
                .font(.system(size: 20, weight: .bold))
            Spacer()
            if library.isLoading || library.isRefreshing {
                ProgressView().controlSize(.small)
            } else if !favoriteOnly {
                RadioIconButton(systemName: "arrow.clockwise", label: "刷新电台", action: refreshStations)
            }
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var stationContent: some View {
        if library.isLoading && library.stations.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在载入电台…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleStations.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(visibleStations) { station in
                        stationRow(station)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyState: some View {
        let isFavoritesEmpty = favoriteOnly && searchText.isEmpty
        let isError = library.errorMessage != nil

        return RadioEmptyStateView(
            symbol: isFavoritesEmpty ? "heart" : (isError ? "wifi.exclamationmark" : "magnifyingglass"),
            title: isFavoritesEmpty ? "还没有收藏电台" : (library.errorMessage ?? "没有找到匹配的电台"),
            detail: isFavoritesEmpty ? "点击电台旁的心形即可收藏。" : "试试其他关键词，或稍后重试。",
            actionTitle: isError ? "重试" : nil,
            action: refreshStations
        )
        .frame(maxHeight: .infinity)
    }

    private func stationRow(_ station: Station) -> some View {
        let isCurrent = player.currentStation?.id == station.id
        let status = isCurrent ? player.playbackStatus : nil

        return StationRowView(
            station: RadioStationInfo(station: station),
            status: status,
            isFavorite: library.isFavorite(station),
            isCurrent: isCurrent,
            isPlaying: isCurrent && player.isPlaying,
            onPlay: {
                if isCurrent {
                    player.togglePlayback()
                } else {
                    player.play(station)
                }
                onSelectStation()
            },
            onFavorite: { library.toggleFavorite(station) }
        )
    }

    private func loadStations() {
        library.show(
            search: StationSearch(query: searchText),
            favoritesOnly: favoriteOnly
        )
    }

    private func refreshStations() {
        library.show(
            search: StationSearch(query: searchText),
            favoritesOnly: favoriteOnly,
            forceRefresh: true
        )
    }
}
