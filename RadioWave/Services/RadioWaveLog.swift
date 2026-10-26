import Foundation
import OSLog

enum RadioWaveLog {
    private static let subsystem = "com.logeable.RadioWave"

    static func debug(_ message: String, category: String) {
        write(.debug, message, category: category)
    }

    static func info(_ message: String, category: String) {
        write(.info, message, category: category)
    }

    static func warning(_ message: String, category: String) {
        write(.default, message, category: category)
    }

    static func error(_ message: String, category: String) {
        write(.error, message, category: category)
    }

    static func errorSummary(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) (\(error.code))"
    }

    private static func write(_ level: OSLogType, _ message: String, category: String) {
        Logger(subsystem: subsystem, category: category).log(level: level, "\(message, privacy: .public)")
        RadioWaveFileLog.shared.append(level: level, category: category, message: message)
    }
}

private final class RadioWaveFileLog: @unchecked Sendable {
    static let shared = RadioWaveFileLog()

    private let queue = DispatchQueue(label: "com.logeable.RadioWave.file-log")
    private let fileManager = FileManager.default
    private let logURL: URL
    private let formatter = ISO8601DateFormatter()
    private let maximumFileSize = 5 * 1024 * 1024

    private init() {
        let libraryFolder = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        logURL = libraryFolder
            .appending(path: "Logs/RadioWave", directoryHint: .isDirectory)
            .appending(path: "RadioWave.log")
    }

    func append(level: OSLogType, category: String, message: String) {
        queue.async { [self] in
            let levelName: String
            switch level {
            case .debug: levelName = "DEBUG"
            case .info: levelName = "INFO"
            case .default: levelName = "WARN"
            case .error: levelName = "ERROR"
            case .fault: levelName = "FAULT"
            default: levelName = "LOG"
            }

            let timestamp = formatter.string(from: Date())
            let entry = Data("\(timestamp) [\(levelName)] [\(category)] \(message)\n".utf8)

            do {
                try fileManager.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try rotateIfNeeded(forNextEntrySize: entry.count)
                if !fileManager.fileExists(atPath: logURL.path) {
                    fileManager.createFile(atPath: logURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: entry)
                try handle.close()
            } catch {
                // Unified logging remains available if the file cannot be written.
            }
        }
    }

    private func rotateIfNeeded(forNextEntrySize size: Int) throws {
        guard fileManager.fileExists(atPath: logURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let currentSize = attributes[.size] as? NSNumber,
              currentSize.intValue + size > maximumFileSize else { return }

        let backupURL = logURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: backupURL)
        try fileManager.moveItem(at: logURL, to: backupURL)
    }
}
