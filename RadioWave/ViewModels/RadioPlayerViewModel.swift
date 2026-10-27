import AVFoundation
import AppKit
import Combine

@MainActor
final class RadioPlayerViewModel: ObservableObject {
    @Published private(set) var currentStation: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var isConnecting = false
    @Published private(set) var playbackError: String?
    @Published private(set) var nowPlayingTitle: String?
    @Published private(set) var generatedBackgroundImage: NSImage?
    @Published private(set) var audioBands = AudioBandLevels.zero
    @Published var volume = 1.0 {
        didSet {
            player.volume = Float(volume)
            directStreamPlayer?.setVolume(Float(volume))
            if volume > 0 { lastNonMutedVolume = volume }
        }
    }

    private let player = AVPlayer()
    private var directStreamPlayer: LivePCMRadioPlayer?
    private var directPlaybackHasStarted = false
    private let api: RadioBrowserAPI
    private let playbackStore: PlaybackStateStore
    private let imageGeneration = ImageGenerationService.shared
    private let historyStore: PlaybackHistoryStore?
    private let icyMetadataReader = ICYMetadataReader()
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: RadioStreamMetadataDelegate?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playbackGeneration = UUID()
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var playbackPreparationTask: Task<Void, Never>?
    private var playbackRecoveryTask: Task<Void, Never>?
    private var playbackItemNotificationObservers: [NSObjectProtocol] = []
    private var visualizationReadyProbeGeneration: UUID?
    private var playbackRecoveryAttempts = 0
    private var isUserPaused = false
    private var audioLevelPollingTask: Task<Void, Never>?
    private var imageGenerationTask: Task<Void, Never>?
    private var imageGenerationSettingsObserver: AnyCancellable?
    private var imageGenerationEnabledObserver: AnyCancellable?
    private let audioLevelMeter = AudioLevelMeter()
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
        let imageGenerationSettings = [
            imageGeneration.$baseURL.map { _ in () }.eraseToAnyPublisher(),
            imageGeneration.$apiKey.map { _ in () }.eraseToAnyPublisher(),
            imageGeneration.$selectedModel.map { _ in () }.eraseToAnyPublisher()
        ]
        imageGenerationSettingsObserver = Publishers.MergeMany(imageGenerationSettings)
            .dropFirst(imageGenerationSettings.count)
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          let title = self.nowPlayingTitle,
                          self.imageGeneration.isEnabled,
                          self.imageGeneration.isConfigured else { return }
                    self.generateBackground(for: title)
                }
            }
        imageGenerationEnabledObserver = imageGeneration.$isEnabled
            .dropFirst()
            .sink { [weak self] isEnabled in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard isEnabled else {
                        self.imageGenerationTask?.cancel()
                        self.imageGenerationTask = nil
                        self.generatedBackgroundImage = nil
                        return
                    }

                    guard let title = self.nowPlayingTitle,
                          self.imageGeneration.isConfigured else { return }
                    self.generateBackground(for: title)
                }
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
        playbackRecoveryTask?.cancel()
        playbackRecoveryTask = nil
        playbackRecoveryAttempts = 0
        startPlayback(station)
    }

    private func startPlayback(_ station: Station) {
        isUserPaused = false
        playbackPreparationTask?.cancel()
        imageGenerationTask?.cancel()
        stopAudioLevelPolling()
        audioLevelMeter.reset(stationUUID: station.stationuuid)
        finishActiveHistorySession()
        directStreamPlayer?.stop()
        directStreamPlayer = nil
        directPlaybackHasStarted = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerItemStatusObservation = nil
        removePlaybackItemNotificationObservers()
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
        RadioWaveLog.info(
            "Starting station \(station.stationuuid), directoryCodec=\(station.codec ?? "unknown"), directoryBitrate=\(station.bitrate.map(String.init) ?? "unknown") kbps, stream=\(Self.redactedStreamAddress(streamURL))",
            category: "PlaybackVisualization"
        )
        isConnecting = true
        icyMetadataReader.start(url: streamURL, stationUUID: station.stationuuid) { [weak self] title in
            guard let self, self.playbackGeneration == generation else { return }
            self.receiveMetadata(title, source: "ICY")
        }
        metadataOutput = nil
        metadataDelegate = nil

        if Self.shouldUseDirectPCM(for: station, streamURL: streamURL) {
            startDirectPCMPlayback(station: station, streamURL: streamURL, generation: generation)
            return
        }

        startAVPlayerPlayback(station: station, streamURL: streamURL, generation: generation)
    }

    private static func shouldUseDirectPCM(for station: Station, streamURL: URL) -> Bool {
        let pathExtension = streamURL.pathExtension.lowercased()
        guard !["m3u8", "m3u", "pls", "ogg", "opus"].contains(pathExtension) else { return false }
        let codec = (station.codec ?? "").lowercased()
        return codec.contains("mp3") || codec.contains("mpeg") || codec.contains("aac")
    }

    private func startDirectPCMPlayback(station: Station, streamURL: URL, generation: UUID) {
        let directPlayer = LivePCMRadioPlayer(
            stationUUID: station.stationuuid,
            codecHint: station.codec ?? "",
            meter: audioLevelMeter,
            onPlaybackStarted: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.playbackGeneration == generation,
                          self.directStreamPlayer != nil else { return }
                    self.directPlaybackHasStarted = true
                    guard !self.isUserPaused else { return }
                    self.isConnecting = false
                    self.isPlaying = true
                    self.playbackError = nil
                    self.playbackRecoveryAttempts = 0
                    self.beginOrResumeHistorySession()
                    self.startAudioLevelPolling()
                    self.api.recordClick(for: station)
                }
            },
            onFailure: { [weak self] message, hasProducedAudio in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.playbackGeneration == generation,
                          self.directStreamPlayer != nil else { return }
                    RadioWaveLog.warning("Direct PCM playback failed for station \(station.stationuuid): \(message)", category: "Playback")
                    if !hasProducedAudio {
                        self.directStreamPlayer?.stop()
                        self.directStreamPlayer = nil
                        self.startAVPlayerPlayback(station: station, streamURL: streamURL, generation: generation)
                        return
                    }
                    self.isConnecting = false
                    self.isPlaying = false
                    self.checkpointAndPauseHistoryTiming()
                    self.stopAudioLevelPolling()
                    self.schedulePlaybackRecovery(after: .seconds(2), reason: "direct PCM stream failed")
                }
            }
        )
        directStreamPlayer = directPlayer
        directPlayer.setVolume(Float(volume))
        directPlayer.start(url: streamURL)
    }

    private func startAVPlayerPlayback(station: Station, streamURL: URL, generation: UUID) {

        let asset = AVURLAsset(url: streamURL)
        let item = AVPlayerItem(asset: asset)
        playerItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let error = observedItem.error
            Task { @MainActor [weak self] in
                guard let self,
                      self.player.currentItem === observedItem,
                      self.playbackGeneration == generation else { return }
                if status == .readyToPlay {
                    await self.logReadyAudioTrackProbe(
                        for: observedItem,
                        station: station,
                        generation: generation
                    )
                }
                if status == .failed {
                    self.isConnecting = false
                    self.isPlaying = false
                    self.playbackError = error?.localizedDescription ?? "无法连接到这个电台。"
                    RadioWaveLog.error("Playback item failed for station \(station.stationuuid): \(error.map(RadioWaveLog.errorSummary) ?? "unknown error")", category: "Playback")
                    self.schedulePlaybackRecovery(after: .seconds(2), reason: "playback item status failed")
                }
            }
        }
        observePlaybackItem(item, station: station, generation: generation)
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

        playbackPreparationTask = Task { @MainActor [weak self] in
            var audioTracks: [AVAssetTrack] = []
            do {
                audioTracks = try await asset.loadTracks(withMediaType: .audio)
            } catch {
                RadioWaveLog.debug("Unable to inspect audio track for visualization: \(RadioWaveLog.errorSummary(error))", category: "Playback")
            }

            guard let self,
                  !Task.isCancelled,
                  self.playbackGeneration == generation else { return }

            var trackDetails: [String] = []
            for track in audioTracks {
                let descriptions = (try? await track.load(.formatDescriptions)) ?? []
                let enabled = (try? await track.load(.isEnabled)) ?? false
                let formats = descriptions.map { Self.fourCharacterCode(CMFormatDescriptionGetMediaSubType($0)) }
                trackDetails.append(
                    "id=\(track.trackID), mediaType=\(track.mediaType.rawValue), enabled=\(enabled), formats=\(formats.isEmpty ? "unknown" : formats.joined(separator: ","))"
                )
            }
            RadioWaveLog.info(
                "Audio track probe for station \(station.stationuuid): count=\(audioTracks.count), tracks=[\(trackDetails.joined(separator: "; "))]",
                category: "PlaybackVisualization"
            )

            if let audioTrack = audioTracks.first {
                do {
                    item.audioMix = try AudioLevelTap.makeMix(for: audioTrack, meter: self.audioLevelMeter)
                    RadioWaveLog.info("Audio tap attached to station \(station.stationuuid), trackID=\(audioTrack.trackID)", category: "PlaybackVisualization")
                } catch {
                    RadioWaveLog.warning("Audio tap creation failed for station \(station.stationuuid): \(RadioWaveLog.errorSummary(error))", category: "PlaybackVisualization")
                }
            } else {
                RadioWaveLog.warning("No audio track found for station \(station.stationuuid); visualization tap was not attached", category: "PlaybackVisualization")
            }

            self.player.replaceCurrentItem(with: item)
            self.player.play()
            self.api.recordClick(for: station)
            self.playbackPreparationTask = nil
        }
    }

    private func logReadyAudioTrackProbe(
        for item: AVPlayerItem,
        station: Station,
        generation: UUID
    ) async {
        guard visualizationReadyProbeGeneration != generation else { return }
        visualizationReadyProbeGeneration = generation

        let itemAudioTrack = item.tracks
            .compactMap(\.assetTrack)
            .first { $0.mediaType == .audio }
        if let itemAudioTrack {
            if item.audioMix == nil {
                do {
                    item.audioMix = try AudioLevelTap.makeMix(for: itemAudioTrack, meter: audioLevelMeter)
                    RadioWaveLog.info(
                        "Audio tap attached from ready item track for station \(station.stationuuid), trackID=\(itemAudioTrack.trackID), mediaType=\(itemAudioTrack.mediaType.rawValue)",
                        category: "PlaybackVisualization"
                    )
                } catch {
                    RadioWaveLog.warning(
                        "Audio tap creation failed for ready item track, station=\(station.stationuuid), trackID=\(itemAudioTrack.trackID): \(RadioWaveLog.errorSummary(error))",
                        category: "PlaybackVisualization"
                    )
                }
            } else {
                RadioWaveLog.info(
                    "Ready item already has an audio mix for station \(station.stationuuid), trackID=\(itemAudioTrack.trackID)",
                    category: "PlaybackVisualization"
                )
            }
        } else {
            RadioWaveLog.warning(
                "Ready item has no audio asset track for station \(station.stationuuid); itemTrackCount=\(item.tracks.count)",
                category: "PlaybackVisualization"
            )
        }

        do {
            let assetTracks = try await item.asset.loadTracks(withMediaType: .audio)
            guard player.currentItem === item, playbackGeneration == generation else { return }

            var details: [String] = []
            for track in assetTracks {
                let descriptions = (try? await track.load(.formatDescriptions)) ?? []
                let enabled = (try? await track.load(.isEnabled)) ?? false
                let formats = descriptions.map { Self.fourCharacterCode(CMFormatDescriptionGetMediaSubType($0)) }
                details.append(
                    "id=\(track.trackID), mediaType=\(track.mediaType.rawValue), enabled=\(enabled), formats=\(formats.isEmpty ? "unknown" : formats.joined(separator: ","))"
                )
            }

            var itemTrackDetails: [String] = []
            for itemTrack in item.tracks {
                guard let assetTrack = itemTrack.assetTrack else {
                    itemTrackDetails.append("assetTrack=unavailable, enabled=\(itemTrack.isEnabled)")
                    continue
                }
                let descriptions = (try? await assetTrack.load(.formatDescriptions)) ?? []
                let formats = descriptions.map { Self.fourCharacterCode(CMFormatDescriptionGetMediaSubType($0)) }
                itemTrackDetails.append(
                    "assetTrackID=\(assetTrack.trackID), mediaType=\(assetTrack.mediaType.rawValue), enabled=\(itemTrack.isEnabled), formats=\(formats.isEmpty ? "unknown" : formats.joined(separator: ","))"
                )
            }
            RadioWaveLog.info(
                "Ready audio track probe for station \(station.stationuuid): itemStatus=\(item.status.rawValue), itemTracks=\(item.tracks.count), audioAssetTracks=\(assetTracks.count), assetTracks=[\(details.joined(separator: "; "))], itemTrackDetails=[\(itemTrackDetails.joined(separator: "; "))]",
                category: "PlaybackVisualization"
            )
        } catch {
            RadioWaveLog.warning(
                "Ready audio track probe failed for station \(station.stationuuid), itemStatus=\(item.status.rawValue): \(RadioWaveLog.errorSummary(error))",
                category: "PlaybackVisualization"
            )
        }
    }

    private static func redactedStreamAddress(_ url: URL) -> String {
        let address = "\(url.scheme ?? "unknown")://\(url.host ?? "unknown")"
        let pathExtension = url.pathExtension
        return pathExtension.isEmpty ? address : "\(address) (extension=\(pathExtension))"
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        let value = String(bytes: bytes, encoding: .macOSRoman)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? String(format: "0x%08x", code) : value
    }

    func togglePlayback() {
        guard let currentStation else { return }
        if playbackError != nil {
            play(currentStation)
            return
        }
        if isPlaying || isConnecting {
            isUserPaused = true
            playbackRecoveryTask?.cancel()
            playbackRecoveryTask = nil
            if directStreamPlayer != nil {
                directStreamPlayer?.pause()
            } else {
                player.pause()
            }
            isPlaying = false
            isConnecting = false
            checkpointAndPauseHistoryTiming()
            stopAudioLevelPolling()
            icyMetadataReader.stop()
        } else if let directStreamPlayer {
            isUserPaused = false
            directStreamPlayer.resume()
            isConnecting = !directPlaybackHasStarted
            isPlaying = directPlaybackHasStarted
            if directPlaybackHasStarted {
                beginOrResumeHistorySession()
                startAudioLevelPolling()
            }
            let generation = playbackGeneration
            if let streamURL = currentStation.streamURL {
                icyMetadataReader.start(url: streamURL, stationUUID: currentStation.stationuuid) { [weak self] title in
                    guard let self, self.playbackGeneration == generation else { return }
                    self.receiveMetadata(title, source: "ICY")
                }
            }
        } else if player.currentItem == nil || player.currentItem?.status == .failed {
            isUserPaused = false
            play(currentStation)
        } else {
            isUserPaused = false
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
        guard directStreamPlayer == nil else { return }
        switch status {
        case .playing:
            playbackRecoveryTask?.cancel()
            playbackRecoveryTask = nil
            playbackRecoveryAttempts = 0
            isConnecting = false
            playbackError = nil
            isPlaying = true
            beginOrResumeHistorySession()
            startAudioLevelPolling()
        case .waitingToPlayAtSpecifiedRate:
            isConnecting = true
            isPlaying = false
            checkpointAndPauseHistoryTiming()
            stopAudioLevelPolling()
            schedulePlaybackRecovery(after: .seconds(20), reason: "playback remained in waiting state")
        case .paused:
            isConnecting = false
            isPlaying = false
            checkpointAndPauseHistoryTiming()
            stopAudioLevelPolling()
            if !isUserPaused, player.currentItem != nil, playbackError == nil {
                schedulePlaybackRecovery(after: .seconds(8), reason: "player paused unexpectedly")
            }
        @unknown default:
            isConnecting = false
            isPlaying = false
            checkpointAndPauseHistoryTiming()
            stopAudioLevelPolling()
        }
    }

    private func observePlaybackItem(_ item: AVPlayerItem, station: Station, generation: UUID) {
        let stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                RadioWaveLog.warning("Playback stalled for station \(station.stationuuid)", category: "Playback")
                self.schedulePlaybackRecovery(after: .seconds(8), reason: "playback stalled")
            }
        }
        let failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                RadioWaveLog.error("Playback ended with an error for station \(station.stationuuid): \(error.map(RadioWaveLog.errorSummary) ?? "unknown error")", category: "Playback")
                self.schedulePlaybackRecovery(after: .seconds(2), reason: "playback item failed")
            }
        }
        playbackItemNotificationObservers = [stalledObserver, failedObserver]
    }

    private func removePlaybackItemNotificationObservers() {
        playbackItemNotificationObservers.forEach(NotificationCenter.default.removeObserver)
        playbackItemNotificationObservers.removeAll()
    }

    private func schedulePlaybackRecovery(after delay: Duration, reason: String) {
        guard let station = currentStation else { return }
        playbackRecoveryTask?.cancel()
        let generation = playbackGeneration
        playbackRecoveryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self,
                  self.playbackGeneration == generation,
                  self.currentStation?.stationuuid == station.stationuuid,
                  self.directStreamPlayer == nil ? self.player.timeControlStatus != .playing : !self.isPlaying else { return }

            guard self.playbackRecoveryAttempts < 3 else {
                self.isConnecting = false
                self.isPlaying = false
                self.playbackError = "连接中断，请点击播放按钮重试。"
                RadioWaveLog.error("Playback recovery exhausted for station \(station.stationuuid)", category: "Playback")
                self.playbackRecoveryTask = nil
                return
            }

            self.playbackRecoveryAttempts += 1
            RadioWaveLog.warning("Reconnecting to station \(station.stationuuid), attempt \(self.playbackRecoveryAttempts) (\(reason))", category: "Playback")
            self.startPlayback(station)
            self.playbackRecoveryTask = nil
        }
    }

    private func startAudioLevelPolling() {
        guard audioLevelPollingTask == nil else { return }
        audioLevelPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let measuredBands = self.audioLevelMeter.currentBands
                let nextBands = AudioBandLevels(
                    bass: max(self.normalizedBandLevel(measuredBands.bass), self.audioBands.bass * 0.82),
                    mid: max(self.normalizedBandLevel(measuredBands.mid), self.audioBands.mid * 0.82),
                    treble: max(self.normalizedBandLevel(measuredBands.treble), self.audioBands.treble * 0.82)
                )
                if abs(self.audioBands.bass - nextBands.bass) > 0.002
                    || abs(self.audioBands.mid - nextBands.mid) > 0.002
                    || abs(self.audioBands.treble - nextBands.treble) > 0.002 {
                    self.audioBands = nextBands
                }
                do {
                    try await Task.sleep(for: .milliseconds(20))
                } catch {
                    return
                }
            }
        }
    }

    private func stopAudioLevelPolling() {
        audioLevelPollingTask?.cancel()
        audioLevelPollingTask = nil
        audioBands = .zero
    }

    private func normalizedBandLevel(_ level: Double) -> Double {
        let outputLevel = level * volume
        let decibels = 20 * log10(max(outputLevel, 0.00001))
        return min(max((decibels + 54) / 48, 0), 1)
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
        if changed {
            generateBackground(for: title)
        }
    }

    private func generateBackground(for title: String) {
        guard imageGeneration.isEnabled, imageGeneration.isConfigured else { return }
        imageGenerationTask?.cancel()
        imageGenerationTask = Task { [weak self, imageGeneration] in
            let image = await imageGeneration.generateBackground(for: title)
            guard !Task.isCancelled,
                  let self,
                  self.nowPlayingTitle == title else { return }
            if let image {
                self.generatedBackgroundImage = image
            }
            self.imageGenerationTask = nil
        }
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
