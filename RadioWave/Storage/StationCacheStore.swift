import Foundation

final class StationCacheStore {
    private let schemaVersion = 2
    private let fileManager: FileManager
    private let fileURL: URL
    private var directory: StationCacheEntry?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportFolder = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "RadioWave", directoryHint: .isDirectory)
        fileURL = supportFolder.appending(path: "station-cache.json")
        if let data = try? Data(contentsOf: fileURL),
           let savedDirectory = try? JSONDecoder().decode(StationCacheEntry.self, from: data),
           savedDirectory.schemaVersion == schemaVersion {
            directory = savedDirectory
        }
    }

    func loadDirectory() -> StationCacheEntry? {
        directory
    }

    func saveDirectory(_ stations: [Station], at date: Date = Date()) {
        directory = StationCacheEntry(schemaVersion: schemaVersion, stations: stations, updatedAt: date)
        persist()
    }

    func clearDirectory() {
        directory = nil
        try? fileManager.removeItem(at: fileURL)
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let directory else { return }
            let data = try JSONEncoder().encode(directory)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Keep cached data in memory if disk storage is unavailable.
        }
    }
}
