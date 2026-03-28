import Foundation
import SQLite3
import AppKit

// MARK: - HistoryEntry

struct HistoryEntry: Identifiable {
    let id: String
    let timestamp: Date
    let mode: String
    let thumbnailData: Data?
    let firstLine: String
    let fullResponse: String
    let queryText: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        mode: String,
        thumbnailData: Data? = nil,
        firstLine: String,
        fullResponse: String,
        queryText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.thumbnailData = thumbnailData
        self.firstLine = firstLine
        self.fullResponse = fullResponse
        self.queryText = queryText
    }
}

// MARK: - HistoryManager

final class HistoryManager {

    static let shared = HistoryManager()

    private var db: OpaquePointer?

    private init() {}

    // MARK: - Open / Setup

    func open() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("ai.presto.PrestoAI", isDirectory: true)

        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let dbPath = folder.appendingPathComponent("history.db").path

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("[HistoryManager] Failed to open database at \(dbPath)")
            return
        }

        let createTable = """
            CREATE TABLE IF NOT EXISTS history (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                mode TEXT NOT NULL,
                thumbnail BLOB,
                first_line TEXT NOT NULL,
                full_response TEXT NOT NULL,
                query_text TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_history_timestamp ON history(timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_history_mode ON history(mode);
            """

        if sqlite3_exec(db, createTable, nil, nil, nil) != SQLITE_OK {
            let err = String(cString: sqlite3_errmsg(db))
            print("[HistoryManager] Schema setup failed: \(err)")
        }
    }

    // MARK: - Insert

    func insert(_ entry: HistoryEntry) {
        let sql = """
            INSERT OR REPLACE INTO history (id, timestamp, mode, thumbnail, first_line, full_response, query_text)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (entry.id as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, (entry.mode as NSString).utf8String, -1, nil)

        if let thumb = entry.thumbnailData {
            thumb.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(thumb.count), nil)
            }
        } else {
            sqlite3_bind_null(stmt, 4)
        }

        sqlite3_bind_text(stmt, 5, (entry.firstLine as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (entry.fullResponse as NSString).utf8String, -1, nil)

        if let q = entry.queryText {
            sqlite3_bind_text(stmt, 7, (q as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(db))
            print("[HistoryManager] Insert failed: \(err)")
        }
    }

    // MARK: - Fetch

    func fetch(limit: Int = 50, offset: Int = 0, mode: String? = nil) -> [HistoryEntry] {
        var sql = "SELECT id, timestamp, mode, thumbnail, first_line, full_response, query_text FROM history"
        if mode != nil {
            sql += " WHERE mode = ?"
        }
        sql += " ORDER BY timestamp DESC LIMIT ? OFFSET ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        if let mode = mode {
            sqlite3_bind_text(stmt, idx, (mode as NSString).utf8String, -1, nil)
            idx += 1
        }
        sqlite3_bind_int(stmt, idx, Int32(limit))
        sqlite3_bind_int(stmt, idx + 1, Int32(offset))

        var results: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(entryFromRow(stmt))
        }
        return results
    }

    // MARK: - Search

    func search(query: String, limit: Int = 30) -> [HistoryEntry] {
        let sql = """
            SELECT id, timestamp, mode, thumbnail, first_line, full_response, query_text
            FROM history
            WHERE first_line LIKE ? OR full_response LIKE ?
            ORDER BY timestamp DESC
            LIMIT ?;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 3, Int32(limit))

        var results: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(entryFromRow(stmt))
        }
        return results
    }

    // MARK: - Delete

    func delete(id: String) {
        let sql = "DELETE FROM history WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(db))
            print("[HistoryManager] Delete failed: \(err)")
        }
    }

    // MARK: - Clear All

    func clearAll() {
        let sql = "DELETE FROM history;"
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let err = String(cString: sqlite3_errmsg(db))
            print("[HistoryManager] Clear all failed: \(err)")
        }
    }

    // MARK: - Prune

    func pruneOlderThan(days: Int = 90) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let sql = "DELETE FROM history WHERE timestamp < ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, cutoff)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(db))
            print("[HistoryManager] Prune failed: \(err)")
        }
    }

    // MARK: - Thumbnail Generation

    static func generateThumbnail(from base64: String, maxWidth: CGFloat = 200) -> Data? {
        guard let data = Data(base64Encoded: base64),
              let image = NSImage(data: data) else { return nil }

        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let scale = min(maxWidth / originalSize.width, 1.0)
        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5])
    }

    // MARK: - Row Parsing

    private func entryFromRow(_ stmt: OpaquePointer?) -> HistoryEntry {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let mode = String(cString: sqlite3_column_text(stmt, 2))

        var thumbnailData: Data?
        if sqlite3_column_type(stmt, 3) != SQLITE_NULL,
           let blob = sqlite3_column_blob(stmt, 3) {
            let len = Int(sqlite3_column_bytes(stmt, 3))
            thumbnailData = Data(bytes: blob, count: len)
        }

        let firstLine = String(cString: sqlite3_column_text(stmt, 4))
        let fullResponse = String(cString: sqlite3_column_text(stmt, 5))

        var queryText: String?
        if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
            queryText = String(cString: sqlite3_column_text(stmt, 6))
        }

        return HistoryEntry(
            id: id,
            timestamp: timestamp,
            mode: mode,
            thumbnailData: thumbnailData,
            firstLine: firstLine,
            fullResponse: fullResponse,
            queryText: queryText
        )
    }
}
