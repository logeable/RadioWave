import AVFoundation
import Combine
import OSLog

@MainActor
final class RadioPlayerViewModel: ObservableObject {
    @Published private(set) var currentStation: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlayingTitle: String?
    @Published var volume = 1.0 {
        didSet { player.volume = Float(volume) }
    }

    private let player = AVPlayer()
    private let api: RadioBrowserAPI
    private let playbackStore: PlaybackStateStore
    private let historyStore: PlaybackHistoryStore?
    private let icyMetadataReader = ICYMetadataReader()
    private let metadataLogger = Logger(subsystem: "com.logeable.RadioWave", category: "PlaybackMetadata")
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: RadioStreamMetadataDelegate?
    private var playbackGeneration = UUID()
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var activeHistorySessionID: UUID?
    private var accumulatedListeningSeconds: TimeInterval = 0
    private var listeningSegmentStartedAt: TimeInterval?
    private var historyCheckpointTask: Task<Void, Never>?

    init(api: RadioBrowserAPI, playbackStore: PlaybackStateStore = PlaybackStateStore()) {
        self.api = api
        self.playbackStore = playbackStore
        do {
            historyStore = try PlaybackHistoryStore()
        } catch {
            historyStore = nil
            NSLog("Unable to open playback history: %@", String(describing: error))
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
        guard let streamURL = station.streamURL else { return }
        finishActiveHistorySession()
        currentStation = station
        playbackStore.saveCurrentStation(station)
        isPlaying = false
        nowPlayingTitle = nil
        playbackGeneration = UUID()
        let generation = playbackGeneration
        icyMetadataReader.start(url: streamURL, stationUUID: station.stationuuid) { [weak self] title in
            guard let self, self.playbackGeneration == generation else { return }
            self.receiveMetadata(title, source: "ICY")
        }
        metadataOutput = nil
        metadataDelegate = nil

        let item = AVPlayerItem(url: streamURL)
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
        metadataLogger.info("Attached AVPlayer metadata output for station \(station.stationuuid, privacy: .public)")

        player.replaceCurrentItem(with: item)
        player.play()
        api.recordClick(for: station)
    }

    func togglePlayback() {
        guard let currentStation else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
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

    private func handlePlayerTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isPlaying = true
            beginOrResumeHistorySession()
        case .paused, .waitingToPlayAtSpecifiedRate:
            isPlaying = false
            checkpointAndPauseHistoryTiming()
        @unknown default:
            isPlaying = false
            checkpointAndPauseHistoryTiming()
        }
    }

    private func beginOrResumeHistorySession() {
        if activeHistorySessionID == nil, let currentStation {
            do {
                activeHistorySessionID = try historyStore?.beginSession(for: currentStation)
            } catch {
                NSLog("Unable to start playback history session: %@", String(describing: error))
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
            NSLog("Unable to finish playback history session: %@", String(describing: error))
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
            NSLog("Unable to save playback history checkpoint: %@", String(describing: error))
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
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            metadataLogger.debug("Metadata event from \(source, privacy: .public) did not contain a title")
            return
        }

        let changed = nowPlayingTitle != title
        metadataLogger.info("Metadata received from \(source, privacy: .public), station=\(self.currentStation?.stationuuid ?? "unknown", privacy: .public), titlePresent=true, changed=\(changed)")
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
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        onTitle(title?.isEmpty == false ? title : nil)
    }
}
