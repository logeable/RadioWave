import Foundation

final class RadioBrowserAPI {
    private let apiRoot = URL(string: "https://de1.api.radio-browser.info")!
    private let userAgent = "RadioWave/1.0 (personal macOS radio player)"
    private let pageSize = 5_000

    func fetchAllStations(progress: @escaping @MainActor (Int, Int?) -> Void) async throws -> [Station] {
        var stations: [Station] = []
        var offset = 0
        let expectedCount = await fetchExpectedStationCount()
        progress(0, expectedCount)

        while true {
            try Task.checkCancellation()
            var components = URLComponents(url: apiRoot.appending(path: "/json/stations"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "order", value: "name"),
                URLQueryItem(name: "reverse", value: "false")
            ]

            var request = URLRequest(url: components.url!)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let page = try JSONDecoder().decode([Station].self, from: data)
            stations.append(contentsOf: page)
            progress(stations.count, expectedCount)

            guard page.count == pageSize else { break }
            offset += page.count
        }

        var uniqueStations: [String: Station] = [:]
        for station in stations {
            uniqueStations[station.stationuuid] = station
        }
        return uniqueStations.values.sorted { ($0.clickcount ?? 0) > ($1.clickcount ?? 0) }
    }

    private func fetchExpectedStationCount() async -> Int? {
        var request = URLRequest(url: apiRoot.appending(path: "/json/stats"))
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let stats = try? JSONDecoder().decode(RadioBrowserStats.self, from: data) else { return nil }
            return max(0, stats.stations - (stats.stationsBroken ?? 0))
        } catch {
            return nil
        }
    }

    func recordClick(for station: Station) {
        let clickURL = apiRoot.appending(path: "/json/url/\(station.stationuuid)")
        var request = URLRequest(url: clickURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request).resume()
    }
}

private struct RadioBrowserStats: Decodable {
    let stations: Int
    let stationsBroken: Int?

    enum CodingKeys: String, CodingKey {
        case stations
        case stationsBroken = "stations_broken"
    }
}
