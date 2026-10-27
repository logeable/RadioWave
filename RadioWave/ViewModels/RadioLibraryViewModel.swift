import Combine
import Foundation

@MainActor
final class RadioLibraryViewModel: ObservableObject {
    @Published private(set) var stations: [Station] = []
    @Published private(set) var favorites: [Station]
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isFiltering = false
    @Published private(set) var isChoosingRandomStation = false
    @Published private(set) var syncProgress = 0
    @Published private(set) var syncProgressTotal: Int?
    @Published private(set) var errorMessage: String?
    @Published private(set) var refreshMessage: String?
    @Published private(set) var cacheUpdatedAt: Date?
    @Published private(set) var countryOptions: [StationFilterOption] = []
    @Published private(set) var tagOptions: [StationFilterOption] = []
    @Published private(set) var languageOptions: [StationFilterOption] = []
    @Published private(set) var codecOptions: [StationFilterOption] = []

    var cachedStationCount: Int { allStations.count }
    var syncProgressPercentage: Int? {
        guard let syncProgressTotal, syncProgressTotal > 0 else { return nil }
        return min(99, Int(Double(syncProgress) / Double(syncProgressTotal) * 100))
    }
    var syncProgressFraction: Double? {
        guard let syncProgressTotal, syncProgressTotal > 0 else { return nil }
        return min(0.99, Double(syncProgress) / Double(syncProgressTotal))
    }

    private let api: RadioBrowserAPI
    private let cacheStore: StationCacheStore
    private let favoritesStore: FavoritesStore
    private var allStations: [Station]
    private var currentSearch = StationSearch(query: "")
    private var showingFavorites = false
    private var syncTask: Task<Void, Never>?
    private var filterWorker: Task<[Station], Never>?
    private var filterTask: Task<Void, Never>?
    private var filterGeneration = UUID()
    private var filterOptionsWorker: Task<StationFilterOptions, Never>?
    private var filterOptionsTask: Task<Void, Never>?
    private var filterOptionsGeneration = UUID()
    private var pendingRandomStationRequests: [(excluding: String?, completion: (Station?) -> Void)] = []

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

    func clearStationCache() {
        guard !isLoading, !isRefreshing else { return }
        allStations = []
        cacheUpdatedAt = nil
        cacheStore.clearDirectory()
        updateFilterOptions()
        applyCurrentFilter()
    }

    func recacheStations() {
        guard !isLoading, !isRefreshing else { return }
        synchronizeDirectory()
    }

    func requestRandomStation(excluding stationID: String?, completion: @escaping (Station?) -> Void) {
        if !allStations.isEmpty {
            completion(randomStation(in: allStations, excluding: stationID))
            return
        }

        pendingRandomStationRequests.append((excluding: stationID, completion: completion))
        isChoosingRandomStation = true
        synchronizeDirectory()
    }

    private func synchronizeDirectory() {
        guard syncTask == nil else { return }
        isLoading = allStations.isEmpty
        isRefreshing = !allStations.isEmpty
        syncProgress = 0
        syncProgressTotal = nil
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
                let downloadedStations = try await api.fetchAllStations { [weak self] count, total in
                    self?.syncProgress = count
                    self?.syncProgressTotal = total
                }
                guard !Task.isCancelled else { return }
                allStations = downloadedStations
                updateFilterOptions()
                cacheStore.saveDirectory(downloadedStations)
                cacheUpdatedAt = Date()
                applyCurrentFilter()
                syncProgress = downloadedStations.count
                syncProgressTotal = downloadedStations.count
                completeRandomStationRequests(using: downloadedStations)
            } catch is CancellationError {
                completeRandomStationRequests(using: nil)
                return
            } catch {
                guard !Task.isCancelled else { return }
                completeRandomStationRequests(using: nil)
                if allStations.isEmpty {
                    errorMessage = "暂时无法加载电台，请检查网络后重试。"
                } else {
                    refreshMessage = "刷新失败，继续显示本地缓存"
                }
            }
        }
    }

    private func randomStation(in stations: [Station], excluding stationID: String?) -> Station? {
        let candidates = stations.filter { $0.id != stationID }
        return (candidates.isEmpty ? stations : candidates).randomElement()
    }

    private func completeRandomStationRequests(using stations: [Station]?) {
        guard !pendingRandomStationRequests.isEmpty else { return }
        let requests = pendingRandomStationRequests
        pendingRandomStationRequests.removeAll()
        isChoosingRandomStation = false

        for request in requests {
            request.completion(stations.flatMap { randomStation(in: $0, excluding: request.excluding) })
        }
    }

    private func applyCurrentFilter() {
        filterWorker?.cancel()
        filterTask?.cancel()

        let generation = UUID()
        filterGeneration = generation
        let search = currentSearch
        let source = showingFavorites ? favorites : allStations
        let favoritesOnly = showingFavorites
        isFiltering = true

        let worker = Task.detached(priority: .userInitiated) {
            Self.filteredStations(source, search: search, favoritesOnly: favoritesOnly)
        }
        filterWorker = worker
        filterTask = Task { @MainActor [weak self] in
            let result = await worker.value
            guard let self, self.filterGeneration == generation else { return }
            self.stations = result
            self.isFiltering = false
            self.errorMessage = favoritesOnly
                ? (result.isEmpty ? "还没有收藏电台。" : nil)
                : (self.allStations.isEmpty ? nil : (result.isEmpty ? "没有找到匹配的电台，试试更短的关键词。" : nil))
            self.filterWorker = nil
            self.filterTask = nil
        }
    }

    nonisolated private static func filteredStations(
        _ source: [Station],
        search: StationSearch,
        favoritesOnly: Bool
    ) -> [Station] {
        guard !favoritesOnly else { return source }
        var results: [Station] = []
        results.reserveCapacity(min(source.count, 512))
        for (index, station) in source.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return [] }
            if !search.query.isEmpty {
                let matchesQuery = [station.name, station.tags ?? "", station.country ?? "", station.language ?? "", station.codec ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(search.query) }
                guard matchesQuery else { continue }
            }
            if let tag = search.tag, !tag.isEmpty, !containsExactValue(tag, in: station.tags) { continue }
            if !search.country.isEmpty,
               (station.country ?? "").localizedCaseInsensitiveCompare(search.country) != .orderedSame { continue }
            if !search.language.isEmpty, !containsExactValue(search.language, in: station.language) { continue }
            if !search.codec.isEmpty,
               (station.codec ?? "").localizedCaseInsensitiveCompare(search.codec) != .orderedSame { continue }
            if search.minimumBitrate > 0, (station.bitrate ?? 0) < search.minimumBitrate { continue }
            results.append(station)
        }

        if Task.isCancelled { return [] }

        switch search.sort {
        case .popular:
            // The directory is already stored in popularity order. Preserve it to avoid
            // sorting a large match set for every keystroke, especially during IME input.
            break
        case .name:
            results.sort { $0.safeName.localizedStandardCompare($1.safeName) == .orderedAscending }
        case .bitrate:
            results.sort { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
        }
        return results
    }

    private func updateFilterOptions() {
        filterOptionsWorker?.cancel()
        filterOptionsTask?.cancel()
        let generation = UUID()
        filterOptionsGeneration = generation
        let source = allStations
        let worker = Task.detached(priority: .utility) {
            Self.makeFilterOptions(from: source)
        }
        filterOptionsWorker = worker
        filterOptionsTask = Task { @MainActor [weak self] in
            let options = await worker.value
            guard let self, self.filterOptionsGeneration == generation else { return }
            self.countryOptions = options.countries
            self.tagOptions = options.tags
            self.languageOptions = options.languages
            self.codecOptions = options.codecs
            self.filterOptionsWorker = nil
            self.filterOptionsTask = nil
        }
    }

    nonisolated private static func makeFilterOptions(from stations: [Station]) -> StationFilterOptions {
        StationFilterOptions(
            countries: makeOptions(from: stations) { [$0.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""] },
            tags: makeOptions(from: stations) { $0.tags?.components(separatedBy: ",") ?? [] },
            languages: makeOptions(from: stations) { $0.language?.components(separatedBy: ",") ?? [] },
            codecs: makeOptions(from: stations) { [$0.codec ?? ""] }
        )
    }

    nonisolated private static func makeOptions(from stations: [Station], values: (Station) -> [String]) -> [StationFilterOption] {
        var labels: [String: String] = [:]
        var counts: [String: Int] = [:]
        for (index, station) in stations.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return [] }
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

    nonisolated private static func containsExactValue(_ soughtValue: String, in rawValues: String?) -> Bool {
        rawValues?.components(separatedBy: ",").contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(soughtValue) == .orderedSame
        } ?? false
    }
}

private struct StationFilterOptions: Sendable {
    let countries: [StationFilterOption]
    let tags: [StationFilterOption]
    let languages: [StationFilterOption]
    let codecs: [StationFilterOption]
}
