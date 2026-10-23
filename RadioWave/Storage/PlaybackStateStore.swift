import Foundation

final class PlaybackStateStore {
    private let defaults: UserDefaults
    private let key = "radiowave.playback.current-station.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadCurrentStation() -> Station? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Station.self, from: data)
    }

    func saveCurrentStation(_ station: Station) {
        guard let data = try? JSONEncoder().encode(station) else { return }
        defaults.set(data, forKey: key)
    }
}
