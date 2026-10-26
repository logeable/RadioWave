import SwiftUI

struct RadioStationInfo: Identifiable {
    let id: String
    let name: String
    let detail: String
    var artwork: Image? = nil
    var artworkURL: URL? = nil

    init(id: String, name: String, detail: String, artwork: Image? = nil, artworkURL: URL? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.artwork = artwork
        self.artworkURL = artworkURL
    }

    init(station: Station) {
        id = station.id
        name = station.safeName
        detail = station.fallbackDetail
        artwork = nil
        artworkURL = station.favicon.flatMap(URL.init(string:))
    }
}

// MARK: - Shared visual tokens
