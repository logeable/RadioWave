import CryptoKit
import Foundation
import ImageIO

/// Keeps downloaded station favicons on disk so they remain available after relaunch.
actor StationIconCache {
    static let shared = StationIconCache()

    private let directory: URL
    private let fileManager = FileManager.default

    private init() {
        let supportFolder = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "RadioWave", directoryHint: .isDirectory)
        directory = supportFolder.appending(path: "station-icons", directoryHint: .isDirectory)
    }

    func data(for url: URL) async -> Data? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }

        let fileURL = cacheURL(for: url)
        if let cachedData = try? Data(contentsOf: fileURL), Self.isImage(cachedData) {
            return cachedData
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  Self.isImage(data) else { return nil }

            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return data
        } catch {
            return nil
        }
    }

    private func cacheURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appending(path: "\(digest).image")
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}
