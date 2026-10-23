import AVFoundation
import Combine

@MainActor
final class RadioPlayerViewModel: ObservableObject {
    @Published private(set) var currentStation: Station?
    @Published private(set) var isPlaying = false
    @Published var volume = 1.0 {
        didSet { player.volume = Float(volume) }
    }

    private let player = AVPlayer()
    private let api: RadioBrowserAPI
    private let playbackStore: PlaybackStateStore

    init(api: RadioBrowserAPI, playbackStore: PlaybackStateStore = PlaybackStateStore()) {
        self.api = api
        self.playbackStore = playbackStore
        currentStation = playbackStore.loadCurrentStation()
        player.volume = Float(volume)
    }

    convenience init() {
        self.init(api: RadioBrowserAPI(), playbackStore: PlaybackStateStore())
    }

    func play(_ station: Station) {
        guard let streamURL = station.streamURL else { return }
        currentStation = station
        playbackStore.saveCurrentStation(station)
        isPlaying = false
        player.replaceCurrentItem(with: AVPlayerItem(url: streamURL))
        player.play()
        isPlaying = true
        api.recordClick(for: station)
    }

    func togglePlayback() {
        guard let currentStation else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else if player.currentItem == nil {
            play(currentStation)
        } else {
            player.play()
            isPlaying = true
        }
    }
}
