import Foundation
import SQLite3

@MainActor
final class PlaybackHistoryStore {
    private static var didRecoverInterruptedSessions = false
    private var database: OpaquePointer?

    init(fileURL: URL? = nil) throws {
        let url: URL
        if let fileURL {
            url = fileURL
        } else {
            let supportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appDirectory = supportDirectory.appending(path: "RadioWave", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            url = appDirectory.appending(path: "play-history.sqlite")
        }

        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let database { sqlite3_close(database) }
            database = nil
            throw PlaybackHistoryStoreError.database(message)
        }

        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS playback_history (
                    id TEXT PRIMARY KEY NOT NULL,
                    station_uuid TEXT NOT NULL,
                    station_name TEXT NOT NULL,
                    opened_at REAL NOT NULL,
                    listened_duration_seconds INTEGER NOT NULL DEFAULT 0,
                    last_checkpoint_at REAL NOT NULL,
                    ended_at REAL
                );
                CREATE INDEX IF NOT EXISTS idx_playback_history_station_opened
                    ON playback_history(station_uuid, opened_at DESC);
                CREATE INDEX IF NOT EXISTS idx_playback_history_opened
                    ON playback_history(opened_at DESC);
                """)
            if !Self.didRecoverInterruptedSessions {
                try recoverInterruptedSessions()
                Self.didRecoverInterruptedSessions = true
            }
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    @discardableResult
    func beginSession(for station: Station, openedAt: Date = Date()) throws -> UUID {
        let id = UUID()
        let statement = try prepare("""
            INSERT INTO playback_history
                (id, station_uuid, station_name, opened_at, listened_duration_seconds, last_checkpoint_at, ended_at)
            VALUES (?, ?, ?, ?, 0, ?, NULL)
            """)
        defer { sqlite3_finalize(statement) }

        bind(id.uuidString, at: 1, to: statement)
        bind(station.stationuuid, at: 2, to: statement)
        bind(station.safeName, at: 3, to: statement)
        sqlite3_bind_double(statement, 4, openedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, openedAt.timeIntervalSince1970)
        try stepDone(statement)
        return id
    }

    func checkpoint(sessionID: UUID, listenedDurationSeconds: Int64, at date: Date = Date()) throws {
        let statement = try prepare("""
            UPDATE playback_history
            SET listened_duration_seconds = ?, last_checkpoint_at = ?
            WHERE id = ? AND ended_at IS NULL
            """)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, max(0, listenedDurationSeconds))
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
        bind(sessionID.uuidString, at: 3, to: statement)
        try stepDone(statement)
    }

    func finishSession(sessionID: UUID, listenedDurationSeconds: Int64, at date: Date = Date()) throws {
        let statement = try prepare("""
            UPDATE playback_history
            SET listened_duration_seconds = ?, last_checkpoint_at = ?, ended_at = ?
            WHERE id = ? AND ended_at IS NULL
            """)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, max(0, listenedDurationSeconds))
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, date.timeIntervalSince1970)
        bind(sessionID.uuidString, at: 4, to: statement)
        try stepDone(statement)
    }

    func history(for stationUUID: String? = nil, limit: Int = 500) throws -> [PlaybackHistoryEntry] {
        let sql: String
        let statement: OpaquePointer?
        if let stationUUID {
            sql = """
                SELECT id, station_uuid, station_name, opened_at, listened_duration_seconds,
                       last_checkpoint_at, ended_at
                FROM playback_history WHERE station_uuid = ? ORDER BY opened_at DESC LIMIT ?
                """
            statement = try prepare(sql)
            bind(stationUUID, at: 1, to: statement)
            sqlite3_bind_int(statement, 2, Int32(max(1, limit)))
        } else {
            sql = """
                SELECT id, station_uuid, station_name, opened_at, listened_duration_seconds,
                       last_checkpoint_at, ended_at
                FROM playback_history ORDER BY opened_at DESC LIMIT ?
                """
            statement = try prepare(sql)
            sqlite3_bind_int(statement, 1, Int32(max(1, limit)))
        }
        guard let statement else { throw PlaybackHistoryStoreError.database("Unable to prepare history query") }
        defer { sqlite3_finalize(statement) }

        var entries: [PlaybackHistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                  let stationUUIDText = sqlite3_column_text(statement, 1),
                  let stationNameText = sqlite3_column_text(statement, 2),
                  let id = UUID(uuidString: String(cString: idText)) else { continue }

            let endedAt = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            entries.append(PlaybackHistoryEntry(
                id: id,
                stationUUID: String(cString: stationUUIDText),
                stationName: String(cString: stationNameText),
                openedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                listenedDurationSeconds: sqlite3_column_int64(statement, 4),
                lastCheckpointAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                endedAt: endedAt
            ))
        }
        return entries
    }

    func summary(for stationUUID: String) throws -> StationPlaybackSummary? {
        let statement = try prepare("""
            SELECT COUNT(*), COALESCE(SUM(listened_duration_seconds), 0), MIN(opened_at), MAX(opened_at)
            FROM playback_history WHERE station_uuid = ?
            """)
        defer { sqlite3_finalize(statement) }
        bind(stationUUID, at: 1, to: statement)

        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_int64(statement, 0) > 0 else { return nil }
        return StationPlaybackSummary(
            playCount: sqlite3_column_int64(statement, 0),
            totalListeningSeconds: sqlite3_column_int64(statement, 1),
            firstPlayedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            lastPlayedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        )
    }

    private func recoverInterruptedSessions() throws {
        try execute("""
            UPDATE playback_history
            SET ended_at = last_checkpoint_at
            WHERE ended_at IS NULL
            """)
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw PlaybackHistoryStoreError.database("Database is unavailable") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw PlaybackHistoryStoreError.database(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else { throw PlaybackHistoryStoreError.database("Database is unavailable") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PlaybackHistoryStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database write failed"
            throw PlaybackHistoryStoreError.database(message)
        }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }
}

private enum PlaybackHistoryStoreError: Error {
    case database(String)
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
