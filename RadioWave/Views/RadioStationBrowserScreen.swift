import SwiftUI

struct RadioStationBrowserScreen: View {
    @ObservedObject var library: RadioLibraryViewModel
    @ObservedObject var player: RadioPlayerViewModel
    let onBack: () -> Void
    let onSelectStation: () -> Void

    @State private var searchText = ""
    @State private var category: RadioStationCategory = .recommended
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var displayedCount = 100

    private var favoriteOnly: Bool { category == .favorites }

    private var visibleStations: [Station] {
        switch category {
        case .recommended:
            return Array(library.stations.prefix(24))
        case .favorites:
            return library.stations
        case .all:
            return Array(library.stations.prefix(displayedCount))
        }
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
        .background(Color.clear)
        .onAppear(perform: loadStations)
        .onChange(of: searchText) { _, _ in
            displayedCount = 100
            debounceSearch()
        }
        .onChange(of: category) { _, _ in
            displayedCount = 100
            loadStations()
        }
        .onDisappear { searchDebounceTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RadioIconButton(systemName: "chevron.left", label: "返回播放器", action: onBack)
            Text("电台列表")
                .font(.system(size: 20, weight: .bold))
            Spacer()
            if library.isLoading || library.isRefreshing || library.isFiltering {
                if let percentage = library.syncProgressPercentage, library.isLoading || library.isRefreshing {
                    Text("\(percentage)%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var stationContent: some View {
        if library.isLoading && library.stations.isEmpty {
            VStack(spacing: 12) {
                if let progress = library.syncProgressFraction {
                    ProgressView(value: progress)
                        .frame(width: 180)
                    Text("正在缓存电台 · \(library.syncProgressPercentage ?? 0)%")
                } else {
                    ProgressView()
                    Text("正在载入电台…")
                }
                Text("已获取 \(library.syncProgress.formatted()) 个")
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
                    if category == .all, visibleStations.count < library.stations.count {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .onAppear(perform: loadNextPage)
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
        searchDebounceTask?.cancel()
        library.show(
            search: StationSearch(query: searchText),
            favoritesOnly: favoriteOnly
        )
    }

    private func debounceSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            loadStations()
        }
    }

    private func loadNextPage() {
        guard displayedCount < library.stations.count else { return }
        displayedCount = min(displayedCount + 100, library.stations.count)
    }

    private func refreshStations() {
        library.show(
            search: StationSearch(query: searchText),
            favoritesOnly: favoriteOnly,
            forceRefresh: true
        )
    }
}
