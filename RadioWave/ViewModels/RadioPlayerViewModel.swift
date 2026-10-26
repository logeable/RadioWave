import AVFoundation
import Combine

@MainActor
final class RadioPlayerViewModel: ObservableObject {
    @Published private(set) var currentStation: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var isConnecting = false
    @Published private(set) var playbackError: String?
    @Published private(set) var nowPlayingTitle: String?
    @Published var volume = 1.0 {
        didSet {
            player.volume = Float(volume)
            if volume > 0 { lastNonMutedVolume = volume }
        }
    }

    private let player = AVPlayer()
    private let api: RadioBrowserAPI
    private let playbackStore: PlaybackStateStore
    private let historyStore: PlaybackHistoryStore?
    private let icyMetadataReader = ICYMetadataReader()
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: RadioStreamMetadataDelegate?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playbackGeneration = UUID()
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var activeHistorySessionID: UUID?
    private var accumulatedListeningSeconds: TimeInterval = 0
    private var listeningSegmentStartedAt: TimeInterval?
    private var historyCheckpointTask: Task<Void, Never>?
    private var lastNonMutedVolume = 1.0

    var isMuted: Bool { volume == 0 }

    var playbackStatus: RadioPlaybackStatus {
        if playbackError != nil { return .failed }
        if isConnecting { return .connecting }
        return isPlaying ? .live : .paused
    }

    init(api: RadioBrowserAPI, playbackStore: PlaybackStateStore? = nil) {
        self.api = api
        let playbackStore = playbackStore ?? PlaybackStateStore()
        self.playbackStore = playbackStore
        do {
            historyStore = try PlaybackHistoryStore()
        } catch {
            historyStore = nil
            RadioWaveLog.error("Unable to open playback history: \(RadioWaveLog.errorSummary(error))", category: "PlaybackHistory")
        }
        currentStation = playbackStore.loadCurrentStation()
        player.volume = Float(volume)
        playerTimeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            let status = observedPlayer.timeControlStatus
            let currentItem = observedPlayer.currentItem
            Task { @MainActor [weak self] in
                guard let self,
                      self.player.currentItem === currentItem,
                      self.player.timeControlStatus == status else { return }
                self.handlePlayerTimeControlStatus(status)
            }
        }
    }

    convenience init() {
        self.init(api: RadioBrowserAPI(), playbackStore: PlaybackStateStore())
    }

    func play(_ station: Station) {
        finishActiveHistorySession()
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerItemStatusObservation = nil
        icyMetadataReader.stop()
        currentStation = station
        playbackStore.saveCurrentStation(station)
        isPlaying = false
        isConnecting = false
        playbackError = nil
        nowPlayingTitle = nil
        playbackGeneration = UUID()
        let generation = playbackGeneration
        guard let streamURL = station.streamURL else {
            playbackError = "这个电台没有可用的播放地址。"
            return
        }
        isConnecting = true
        icyMetadataReader.start(url: streamURL, stationUUID: station.stationuuid) { [weak self] title in
            guard let self, self.playbackGeneration == generation else { return }
            self.receiveMetadata(title, source: "ICY")
        }
        metadataOutput = nil
        metadataDelegate = nil

        let item = AVPlayerItem(url: streamURL)
        playerItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let error = observedItem.error
            Task { @MainActor [weak self] in
                guard let self,
                      self.player.currentItem === observedItem,
                      self.playbackGeneration == generation else { return }
                if status == .failed {
                    self.isConnecting = false
                    self.isPlaying = false
                    self.playbackError = error?.localizedDescription ?? "无法连接到这个电台。"
                }
            }
        }
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        let delegate = RadioStreamMetadataDelegate { [weak self] title in
            Task { @MainActor [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.receiveMetadata(title, source: "AVPlayer")
            }
        }
        output.setDelegate(delegate, queue: .main)
        item.add(output)
        metadataOutput = output
        metadataDelegate = delegate
        RadioWaveLog.debug("Attached AVPlayer metadata output for station \(station.stationuuid)", category: "PlaybackMetadata")

        player.replaceCurrentItem(with: item)
        player.play()
        api.recordClick(for: station)
    }

    func togglePlayback() {
        guard let currentStation else { return }
        if playbackError != nil {
            play(currentStation)
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
            isConnecting = false
            icyMetadataReader.stop()
        } else if player.currentItem == nil {
            play(currentStation)
        } else {
            player.play()
            if let streamURL = currentStation.streamURL {
                let generation = playbackGeneration
                icyMetadataReader.start(url: streamURL, stationUUID: currentStation.stationuuid) { [weak self] title in
                    guard let self, self.playbackGeneration == generation else { return }
                    self.receiveMetadata(title, source: "ICY")
                }
            }
        }
    }

    func toggleMute() {
        volume = isMuted ? lastNonMutedVolume : 0
    }

    private func handlePlayerTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isConnecting = false
            playbackError = nil
            isPlaying = true
            beginOrResumeHistorySession()
        case .waitingToPlayAtSpecifiedRate:
            isConnecting = true
            isPlaying = false
            checkpointAndPauseHistoryTiming()
        case .paused:
            isConnecting = false
            isPlaying = false
            checkpointAndPauseHistoryTiming()
        @unknown default:
            isConnecting = false
            isPlaying = false
            checkpointAndPauseHistoryTiming()
        }
    }

    private func beginOrResumeHistorySession() {
        if activeHistorySessionID == nil, let currentStation {
            do {
                activeHistorySessionID = try historyStore?.beginSession(for: currentStation)
            } catch {
                RadioWaveLog.error("Unable to start playback history session: \(RadioWaveLog.errorSummary(error))", category: "PlaybackHistory")
            }
            accumulatedListeningSeconds = 0
        }

        guard activeHistorySessionID != nil, listeningSegmentStartedAt == nil else { return }
        listeningSegmentStartedAt = ProcessInfo.processInfo.systemUptime
        startHistoryCheckpointing()
    }

    private func checkpointAndPauseHistoryTiming() {
        if let segmentStart = listeningSegmentStartedAt {
            accumulatedListeningSeconds += max(0, ProcessInfo.processInfo.systemUptime - segmentStart)
            listeningSegmentStartedAt = nil
        }
        persistHistoryCheckpoint()
        historyCheckpointTask?.cancel()
        historyCheckpointTask = nil
    }

    private func finishActiveHistorySession() {
        checkpointAndPauseHistoryTiming()
        guard let sessionID = activeHistorySessionID else { return }
        do {
            try historyStore?.finishSession(
                sessionID: sessionID,
                listenedDurationSeconds: Int64(accumulatedListeningSeconds.rounded(.down))
            )
        } catch {
            RadioWaveLog.error("Unable to finish playback history session: \(RadioWaveLog.errorSummary(error))", category: "PlaybackHistory")
        }
        activeHistorySessionID = nil
        accumulatedListeningSeconds = 0
        listeningSegmentStartedAt = nil
    }

    private func persistHistoryCheckpoint() {
        guard let sessionID = activeHistorySessionID else { return }
        let currentSegmentDuration = listeningSegmentStartedAt.map {
            max(0, ProcessInfo.processInfo.systemUptime - $0)
        } ?? 0
        do {
            try historyStore?.checkpoint(
                sessionID: sessionID,
                listenedDurationSeconds: Int64((accumulatedListeningSeconds + currentSegmentDuration).rounded(.down))
            )
        } catch {
            RadioWaveLog.error("Unable to save playback history checkpoint: \(RadioWaveLog.errorSummary(error))", category: "PlaybackHistory")
        }
    }

    private func startHistoryCheckpointing() {
        guard historyCheckpointTask == nil else { return }
        historyCheckpointTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.persistHistoryCheckpoint()
            }
        }
    }

    private func receiveMetadata(_ title: String?, source: String) {
        guard let rawTitle = title else {
            RadioWaveLog.debug("Metadata event from \(source) did not contain a title", category: "PlaybackMetadata")
            return
        }

        let stationUUID = currentStation?.stationuuid ?? "unknown"
        RadioWaveLog.debug(
            "Raw track metadata from \(source), station=\(stationUUID), value=\(rawTitle.debugDescription)",
            category: "PlaybackMetadata"
        )
        let title = rawTitle
            .replacingOccurrences(of: "\\'", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            RadioWaveLog.debug("Metadata event from \(source) contained an empty title", category: "PlaybackMetadata")
            return
        }

        let changed = nowPlayingTitle != title
        RadioWaveLog.debug("Metadata received from \(source), station=\(stationUUID), changed=\(changed)", category: "PlaybackMetadata")
        nowPlayingTitle = title
    }
}

private final class RadioStreamMetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let onTitle: (String?) -> Void

    init(onTitle: @escaping (String?) -> Void) {
        self.onTitle = onTitle
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let title = groups
            .flatMap(\.items)
            .first(where: { $0.identifier == .icyMetadataStreamTitle || $0.commonKey == .commonKeyTitle })?
            .stringValue

        onTitle(title)
    }
}
