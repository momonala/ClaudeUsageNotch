import Foundation
import SQLite3

/// Minimal read-only SQLite reader used to pull OAuth tokens out of other apps'
/// local databases (Perplexity's URL cache, Antigravity's VS Code state store).
///
/// It copies the database — plus any `-wal` / `-shm` sidecars — into a temp file
/// before opening, so we (a) never take a lock on a DB another app is actively
/// writing, and (b) still see rows that are only in the write-ahead log. The
/// copy is deleted immediately after the query.
enum SQLiteReader {

    /// Runs `sql` against a private copy of `dbPath` and returns the rows.
    /// Each cell is a `String`, `Data`, `Int`, `Double`, or `nil`.
    /// Returns `nil` if the file is missing or can't be opened.
    static func query(_ dbPath: String, _ sql: String) -> [[Any?]]? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        guard let copy = makeSnapshot(of: dbPath) else { return nil }
        defer { cleanup(copy) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var rows: [[Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let columnCount = sqlite3_column_count(stmt)
            var row: [Any?] = []
            row.reserveCapacity(Int(columnCount))
            for i in 0..<columnCount {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row.append(Int(sqlite3_column_int64(stmt, i)))
                case SQLITE_FLOAT:
                    row.append(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT:
                    if let c = sqlite3_column_text(stmt, i) { row.append(String(cString: c)) }
                    else { row.append(nil) }
                case SQLITE_BLOB:
                    if let b = sqlite3_column_blob(stmt, i) {
                        row.append(Data(bytes: b, count: Int(sqlite3_column_bytes(stmt, i))))
                    } else { row.append(nil) }
                default:
                    row.append(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: - Snapshot

    private static func makeSnapshot(of dbPath: String) -> URL? {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("notchy-sqlite-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)) != nil else { return nil }
        let src = URL(fileURLWithPath: dbPath)
        let dst = tmpDir.appendingPathComponent(src.lastPathComponent)
        do {
            try fm.copyItem(at: src, to: dst)
        } catch {
            try? fm.removeItem(at: tmpDir)
            return nil
        }
        // Bring the WAL/SHM sidecars along so the snapshot is consistent.
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: dbPath + suffix)
            if fm.fileExists(atPath: sidecar.path) {
                try? fm.copyItem(at: sidecar, to: tmpDir.appendingPathComponent(src.lastPathComponent + suffix))
            }
        }
        return dst
    }

    private static func cleanup(_ copy: URL) {
        try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
    }
}
