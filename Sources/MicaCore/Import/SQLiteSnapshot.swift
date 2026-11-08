import Foundation
import SQLite3

/// Read-only copy of another browser's SQLite database. The browser may hold a lock on the original and keep recent
/// rows in the write-ahead log, so the file and its `-wal` are copied to a private temporary folder first.
public final class SQLiteSnapshot {
    private var db: OpaquePointer?
    private let folder: URL

    public init(_ source: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw ImportError.unreadable(source.lastPathComponent) }
        guard fm.isReadableFile(atPath: source.path) else { throw ImportError.noAccess(source.path) }
        folder = fm.temporaryDirectory.appendingPathComponent("mica-import-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("db.sqlite")
        do { try fm.copyItem(at: source, to: copy) } catch { try? fm.removeItem(at: folder); throw ImportError.noAccess(source.path) }
        let wal = URL(fileURLWithPath: source.path + "-wal")
        if fm.fileExists(atPath: wal.path) { try? fm.copyItem(at: wal, to: URL(fileURLWithPath: copy.path + "-wal")) }
        // Read-write on the private copy lets SQLite fold the copied log into the database.
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db); db = nil; try? fm.removeItem(at: folder)
            throw ImportError.unreadable(source.lastPathComponent)
        }
    }

    deinit { sqlite3_close(db); try? FileManager.default.removeItem(at: folder) }

    public enum Value { case int(Int64), double(Double), text(String), blob(Data), null
        public var int: Int64? { switch self { case .int(let v): return v; case .double(let v): return Int64(v); case .text(let s): return Int64(s); default: return nil } }
        public var text: String? { switch self { case .text(let s): return s; case .int(let v): return String(v); default: return nil } }
        public var data: Data? { switch self { case .blob(let d): return d; case .text(let s): return Data(s.utf8); default: return nil } }
    }

    /// Runs a query and returns every row. Bindings are integers only; the queries here have no user text.
    public func rows(_ sql: String, _ bindings: [Int64] = []) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ImportError.unreadable(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() { sqlite3_bind_int64(statement, Int32(index + 1), value) }
        var result: [[Value]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [Value] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT: row.append(.double(sqlite3_column_double(statement, column)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(statement, column))))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    if let bytes = sqlite3_column_blob(statement, column), count > 0 { row.append(.blob(Data(bytes: bytes, count: count))) } else { row.append(.blob(Data())) }
                default: row.append(.null)
                }
            }
            result.append(row)
        }
        return result
    }

    public func hasTable(_ name: String) -> Bool {
        ((try? rows("SELECT name FROM sqlite_master WHERE type='table'")) ?? []).contains { $0.first?.text == name }
    }
}
