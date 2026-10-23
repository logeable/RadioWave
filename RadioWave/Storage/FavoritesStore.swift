import Foundation

final class FavoritesStore {
    private let defaults: UserDefaults
    private let key = "radiowave.favorites.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Station] {
        guard let data = defaults.data(forKey: key),
              let stations = try? JSONDecoder().decode([Station].self, from: data) else {
            return []
        }
        return stations
    }

    func save(_ stations: [Station]) {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        defaults.set(data, forKey: key)
    }
}
