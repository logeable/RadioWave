import SwiftUI

struct StationBrowserView: View {
    @ObservedObject var library: RadioLibraryViewModel
    @ObservedObject var player: RadioPlayerViewModel
    @Binding var showingFavorites: Bool

    @State private var searchText = ""
    @State private var displayedCount = 100
    @AppStorage("RadioWave.filters.country") private var countryFilter = ""
    @AppStorage("RadioWave.filters.language") private var languageFilter = ""
    @AppStorage("RadioWave.filters.tag") private var tagFilter = ""
    @AppStorage("RadioWave.filters.codec") private var codecFilter = ""
    @AppStorage("RadioWave.filters.minimumBitrate") private var minimumBitrate = 0
    @AppStorage("RadioWave.filters.sort") private var sortRawValue = StationSort.popular.rawValue

    private var sort: StationSort { StationSort(rawValue: sortRawValue) ?? .popular }

    private var activeFilterCount: Int {
        [countryFilter, languageFilter, tagFilter, codecFilter].filter { !$0.isEmpty }.count
            + (minimumBitrate > 0 ? 1 : 0)
            + (sort == .popular ? 0 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if !showingFavorites { quickFilters }
            listSummary
            stationResults
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: loadCurrentList)
        .onChange(of: showingFavorites) { displayedCount = 100; loadCurrentList() }
        .onChange(of: searchText) { displayedCount = 100; loadCurrentList() }
        .onChange(of: filterSnapshot) { applyFilters() }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(RadioPalette.accent)
                Text("RadioWave").font(.system(size: 15, weight: .semibold)).foregroundStyle(RadioPalette.ink)
            }

            Picker("电台列表", selection: $showingFavorites) {
                Text("发现").tag(false)
                Text("收藏").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(RadioPalette.muted)
                TextField("搜索电台", text: $searchText)
                    .textFieldStyle(.plain)
                    .disabled(showingFavorites)
                if !searchText.isEmpty && !showingFavorites {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(RadioPalette.muted)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 11)
            .frame(width: 210, height: 34)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(RadioPalette.line, lineWidth: 1))

        }
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var quickFilters: some View {
        HStack(spacing: 8) {
            FacetDropdown(title: "国家 / 地区", selection: optionalSelection($countryFilter), options: library.countryOptions)
            FacetDropdown(title: "类型", selection: optionalSelection($tagFilter), options: library.tagOptions)
            FacetDropdown(title: "语言", selection: optionalSelection($languageFilter), options: library.languageOptions)

            moreFilters

            if activeFilterCount > 0 {
                Button("清除") { clearFilters() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RadioPalette.accent)
            }
            Spacer(minLength: 0)

            Button(action: playRandomStation) {
                Label("随机播放", systemImage: "shuffle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(RadioPalette.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(library.stations.isEmpty)
            .opacity(library.stations.isEmpty ? 0.5 : 1)
            .help("从当前筛选结果中随机播放一台电台")
            .accessibilityLabel("随机播放当前筛选结果中的电台")
        }
        .padding(.bottom, 12)
    }

    private var moreFilters: some View {
        Menu {
            Menu {
                Button("不限编码") { codecFilter = "" }
                ForEach(library.codecOptions) { option in
                    Button("\(option.title) · \(option.count.formatted())") { codecFilter = option.value }
                }
            } label: {
                Label(codecFilter.isEmpty ? "音频编码" : codecFilter, systemImage: "waveform")
            }

            Menu {
                Button("不限码率") { minimumBitrate = 0 }
                bitrateOption(64)
                bitrateOption(128)
                bitrateOption(192)
                bitrateOption(256)
            } label: {
                Label(minimumBitrate == 0 ? "最低码率" : "≥ \(minimumBitrate) kbps", systemImage: "speedometer")
            }

            Menu {
                ForEach(StationSort.allCases) { option in
                    Button {
                        sortRawValue = option.rawValue
                    } label: {
                        if sort == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Label("排序：\(sort.title)", systemImage: "arrow.up.arrow.down")
            }
        } label: {
            HStack(spacing: 5) {
                Text("更多")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                if (!codecFilter.isEmpty ? 1 : 0) + (minimumBitrate > 0 ? 1 : 0) + (sort == .popular ? 0 : 1) > 0 {
                    Circle().fill(RadioPalette.accent).frame(width: 5, height: 5)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(RadioPalette.ink)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(RadioPalette.line, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
    }

    private func bitrateOption(_ value: Int) -> some View {
        Button {
            minimumBitrate = value
        } label: {
            if minimumBitrate == value {
                Label("≥ \(value) kbps", systemImage: "checkmark")
            } else {
                Text("≥ \(value) kbps")
            }
        }
    }

    private var listSummary: some View {
        HStack(spacing: 8) {
            Text(showingFavorites ? "收藏" : "电台")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(RadioPalette.ink)
            Text(showingFavorites ? "\(library.stations.count)" : "匹配 \(library.stations.count)")
                .font(.system(size: 11)).foregroundStyle(RadioPalette.muted)
            Spacer()
            HStack(spacing: 8) {
                Text(dataStatus)
                    .font(.system(size: 10)).foregroundStyle(library.refreshMessage == nil ? RadioPalette.muted : RadioPalette.accent)
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(RadioPalette.line).frame(height: 1) }
    }

    private var dataStatus: String {
        if library.isLoading || library.isRefreshing {
            return "正在同步 · \(library.syncProgress.formatted())"
        }
        if let refreshMessage = library.refreshMessage { return refreshMessage }
        if showingFavorites { return "" }
        if let updatedAt = library.cacheUpdatedAt {
            return "本地缓存 \(library.cachedStationCount.formatted()) · \(updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        return ""
    }

    @ViewBuilder
    private var stationResults: some View {
        if library.isLoading && library.stations.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                ProgressView().tint(RadioPalette.accent)
                Text(library.syncProgress == 0 ? "正在载入电台…" : "正在缓存更多电台…")
                    .font(.system(size: 12)).foregroundStyle(RadioPalette.muted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = library.errorMessage, library.stations.isEmpty {
            emptyState(error)
        } else {
            stationList
        }
    }

    private var stationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(library.stations.prefix(displayedCount))) { station in
                    StationRow(station: station,
                               isFavorite: library.isFavorite(station),
                               isCurrent: player.currentStation?.id == station.id,
                               isPlaying: player.isPlaying,
                               onPlay: {
                                   if player.currentStation?.id == station.id {
                                       player.togglePlayback()
                                   } else {
                                       player.play(station)
                                   }
                               },
                               onFavorite: { library.toggleFavorite(station) })
                    Rectangle().fill(RadioPalette.line).frame(height: 1)
                }

                if displayedCount < library.stations.count {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small).tint(RadioPalette.muted)
                        Text("正在载入更多电台…")
                            .font(.system(size: 10)).foregroundStyle(RadioPalette.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .onAppear(perform: loadNextPage)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(message).font(.system(size: 13, weight: .medium)).foregroundStyle(RadioPalette.ink)
            Text(showingFavorites ? "点击电台旁的心形即可收藏。" : "检查网络，或换个关键词试试。")
                .font(.system(size: 11)).foregroundStyle(RadioPalette.muted)
            if !showingFavorites {
                Button("重试", action: refreshCurrentList)
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(RadioPalette.accent).padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func loadCurrentList() {
        library.show(search: currentSearch, favoritesOnly: showingFavorites)
    }

    private func refreshCurrentList() {
        library.show(search: currentSearch, favoritesOnly: showingFavorites, forceRefresh: true)
    }

    private var currentSearch: StationSearch {
        StationSearch(query: searchText,
                      tag: tagFilter.isEmpty ? nil : tagFilter,
                      country: countryFilter,
                      language: languageFilter,
                      codec: codecFilter,
                      minimumBitrate: minimumBitrate,
                      sort: sort)
    }

    private func applyFilters() {
        displayedCount = 100
        loadCurrentList()
    }

    private func loadNextPage() {
        guard displayedCount < library.stations.count else { return }
        displayedCount = min(displayedCount + 100, library.stations.count)
    }

    private func playRandomStation() {
        let candidates = library.stations.filter { $0.id != player.currentStation?.id }
        guard let station = candidates.randomElement() ?? library.stations.randomElement() else { return }
        player.play(station)
    }

    private func clearFilters() {
        countryFilter = ""
        languageFilter = ""
        tagFilter = ""
        codecFilter = ""
        minimumBitrate = 0
        sortRawValue = StationSort.popular.rawValue
    }

    private func optionalSelection(_ value: Binding<String>) -> Binding<String?> {
        Binding(
            get: { value.wrappedValue.isEmpty ? nil : value.wrappedValue },
            set: { value.wrappedValue = $0 ?? "" }
        )
    }

    private var filterSnapshot: FilterSnapshot {
        FilterSnapshot(country: countryFilter,
                       language: languageFilter,
                       tag: tagFilter,
                       codec: codecFilter,
                       minimumBitrate: minimumBitrate,
                       sort: sortRawValue)
    }
}

private struct FilterSnapshot: Equatable {
    let country: String
    let language: String
    let tag: String
    let codec: String
    let minimumBitrate: Int
    let sort: String
}

private struct FacetDropdown: View {
    let title: String
    @Binding var selection: String?
    let options: [StationFilterOption]

    @State private var isPresented = false
    @State private var searchText = ""

    private var visibleOptions: [StationFilterOption] {
        guard !searchText.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 6) {
                Text(selection ?? title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11, weight: selection == nil ? .medium : .semibold))
            .foregroundStyle(selection == nil ? RadioPalette.ink : RadioPalette.accent)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .frame(maxWidth: 144)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == nil ? RadioPalette.line : RadioPalette.accent.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(RadioPalette.muted)
                    TextField("搜索\(title)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(8)
                .background(RadioPalette.canvas, in: RoundedRectangle(cornerRadius: 7))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        optionRow(value: nil, title: "不限", count: nil)
                        ForEach(visibleOptions) { option in
                            optionRow(value: option.value, title: option.title, count: option.count)
                        }
                    }
                }
                .frame(height: 260)
                .scrollIndicators(.hidden)
            }
            .padding(12)
            .frame(width: 250)
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { searchText = "" }
        }
    }

    private func optionRow(value: String?, title: String, count: Int?) -> some View {
        Button {
            selection = value
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                if let count {
                    Text(count.formatted()).foregroundStyle(RadioPalette.muted)
                }
                if selection == value {
                    Image(systemName: "checkmark").foregroundStyle(RadioPalette.accent)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(RadioPalette.ink)
            .padding(.horizontal, 7)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
