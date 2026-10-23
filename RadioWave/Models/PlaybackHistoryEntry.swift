import Foundation

struct PlaybackHistoryEntry: Identifiable {
    let id: UUID
    let stationUUID: String
    let stationName: String
    let openedAt: Date
    let listenedDurationSeconds: Int64
    let lastCheckpointAt: Date
    let endedAt: Date?
}

struct StationPlaybackSummary {
    let playCount: Int64
    let totalListeningSeconds: Int64
    let firstPlayedAt: Date?
    let lastPlayedAt: Date?
}
