import Combine
import Foundation

@MainActor
final class RadioLibraryViewModel: ObservableObject {
    @Published private(set) var stations: [Station] = []
    @Published private(set) var favorites: [Station]
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var syncProgress = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var refreshMessage: String?
    @Published private(set) var cacheUpdatedAt: Date?
    @Published private(set) var countryOptions: [StationFilterOption] = []
    @Published private(set) var tagOptions: [StationFilterOption] = []
    @Published private(set) var languageOptions: [StationFilterOption] = []
    @Published private(set) var codecOptions: [StationFilterOption] = []

    var cachedStationCount: Int { allStations.count }

    private let api: RadioBrowserAPI
    private let cacheStore: StationCacheStore
    private let favoritesStore: FavoritesStore
    private var allStations: [Station]
    private var currentSearch = StationSearch(query: "")
    private var showingFavorites = false
    private var syncTask: Task<Void, Never>?

    init(api: RadioBrowserAPI,
         cacheStore: StationCacheStore,
         favoritesStore: FavoritesStore) {
        self.api = api
        self.cacheStore = cacheStore
        self.favoritesStore = favoritesStore

        favorites = favoritesStore.load()
        let cachedDirectory = cacheStore.loadDirectory()
        allStations = cachedDirectory?.stations ?? []
        cacheUpdatedAt = cachedDirectory?.updatedAt
        updateFilterOptions()
    }

    convenience init() {
        self.init(api: RadioBrowserAPI(), cacheStore: StationCacheStore(), favoritesStore: FavoritesStore())
    }

    func show(search: StationSearch, favoritesOnly: Bool, forceRefresh: Bool = false) {
        currentSearch = search
        showingFavorites = favoritesOnly
        applyCurrentFilter()

        guard !favoritesOnly else { return }
        if forceRefresh {
            synchronizeDirectory()
        } else if cacheUpdatedAt == nil {
            synchronizeDirectory()
        }
    }

    func toggleFavorite(_ station: Station) {
        if favorites.contains(where: { $0.id == station.id }) {
            favorites.removeAll { $0.id == station.id }
        } else {
            favorites.insert(station, at: 0)
        }
        favoritesStore.save(favorites)
        if showingFavorites { applyCurrentFilter() }
    }

    func isFavorite(_ station: Station) -> Bool {
        favorites.contains(where: { $0.id == station.id })
    }

    private func synchronizeDirectory() {
        guard syncTask == nil else { return }
        isLoading = allStations.isEmpty
        isRefreshing = !allStations.isEmpty
        syncProgress = 0
        errorMessage = nil
        refreshMessage = nil

        syncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isLoading = false
                isRefreshing = false
                syncTask = nil
            }

            do {
                let downloadedStations = try await api.fetchAllStations { [weak self] count in
                    self?.syncProgress = count
                }
                guard !Task.isCancelled else { return }
                allStations = downloadedStations
                updateFilterOptions()
                cacheStore.saveDirectory(downloadedStations)
                cacheUpdatedAt = Date()
                applyCurrentFilter()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if allStations.isEmpty {
                    errorMessage = "暂时无法加载电台，请检查网络后重试。"
                } else {
                    refreshMessage = "刷新失败，继续显示本地缓存"
                }
            }
        }
    }

    private func applyCurrentFilter() {
        if showingFavorites {
            stations = favorites
            errorMessage = favorites.isEmpty ? "还没有收藏电台。" : nil
            return
        }

        var results = allStations
        if !currentSearch.query.isEmpty {
            results = results.filter { station in
                [station.name, station.tags ?? "", station.country ?? "", station.language ?? "", station.codec ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(currentSearch.query) }
            }
        }
        if let tag = currentSearch.tag, !tag.isEmpty {
            results = results.filter { containsExactValue(tag, in: $0.tags) }
        }
        if !currentSearch.country.isEmpty {
            results = results.filter { ($0.country ?? "").localizedCaseInsensitiveCompare(currentSearch.country) == .orderedSame }
        }
        if !currentSearch.language.isEmpty {
            results = results.filter { containsExactValue(currentSearch.language, in: $0.language) }
        }
        if !currentSearch.codec.isEmpty {
            results = results.filter { ($0.codec ?? "").localizedCaseInsensitiveCompare(currentSearch.codec) == .orderedSame }
        }
        if currentSearch.minimumBitrate > 0 {
            results = results.filter { ($0.bitrate ?? 0) >= currentSearch.minimumBitrate }
        }
        switch currentSearch.sort {
        case .popular:
            stations = results.sorted { ($0.clickcount ?? 0) > ($1.clickcount ?? 0) }
        case .name:
            stations = results.sorted { $0.safeName.localizedStandardCompare($1.safeName) == .orderedAscending }
        case .bitrate:
            stations = results.sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
        }
        errorMessage = allStations.isEmpty ? nil : (stations.isEmpty ? "没有找到匹配的电台，试试更短的关键词。" : nil)
    }

    private func updateFilterOptions() {
        countryOptions = makeOptions(from: allStations) { station in
            [station.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""]
        }
        tagOptions = makeOptions(from: allStations) { station in
            station.tags?.components(separatedBy: ",") ?? []
        }
        languageOptions = makeOptions(from: allStations) { station in
            station.language?.components(separatedBy: ",") ?? []
        }
        codecOptions = makeOptions(from: allStations) { station in
            [station.codec ?? ""]
        }
    }

    private func makeOptions(from stations: [Station], values: (Station) -> [String]) -> [StationFilterOption] {
        var labels: [String: String] = [:]
        var counts: [String: Int] = [:]
        for station in stations {
            let uniqueValues = Set(values(station).compactMap { rawValue -> String? in
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }.map { $0.lowercased() })
            for key in uniqueValues {
                if labels[key] == nil {
                    labels[key] = values(station).first { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? key
                }
                counts[key, default: 0] += 1
            }
        }
        return counts.map { key, count in
            StationFilterOption(value: labels[key] ?? key, count: count)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func containsExactValue(_ soughtValue: String, in rawValues: String?) -> Bool {
        rawValues?.components(separatedBy: ",").contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(soughtValue) == .orderedSame
        } ?? false
    }
}
