import CSQLite
import Foundation

enum SQLiteHelpers {
    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func bindOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value = value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    static func bindOptionalInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value = value {
            sqlite3_bind_int(stmt, index, Int32(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    static func bindOptionalDate(_ stmt: OpaquePointer?, _ index: Int32, _ value: Date?) {
        if let value = value {
            sqlite3_bind_int64(stmt, index, Int64(value.timeIntervalSince1970))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    static func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    static func readOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return sqlite3_column_double(stmt, index)
    }

    static func readOptionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return Int(sqlite3_column_int(stmt, index))
    }

    static func readOptionalDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, index)))
    }

    static func readOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cString)
    }
}
