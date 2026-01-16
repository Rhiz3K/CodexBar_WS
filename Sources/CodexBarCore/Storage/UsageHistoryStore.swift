// UsageHistoryStore.swift
// SQLite-based storage for usage history and statistics
// Cross-platform: macOS and Linux

import CSQLite
import Foundation

// MARK: - Usage History Store

/// SQLite-based store for usage history
public final class UsageHistoryStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.codexbar.usagehistory", qos: .utility)

    private static let schemaVersion = 3

    public init(path: String? = nil) throws {
        if let path = path {
            self.dbPath = path
        } else {
            self.dbPath = Self.defaultDatabasePath()
        }

        try self.openDatabase()
        try self.createTables()
        try self.migrateIfNeeded()
    }

    deinit {
        if self.db != nil {
            sqlite3_close(self.db)
        }
    }

    // MARK: - Database Path

    public static func defaultDatabasePath() -> String {
        #if os(macOS)
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("CodexBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage_history.sqlite").path
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".codexbar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage_history.sqlite").path
        #endif
    }

    // MARK: - Database Setup

    private func openDatabase() throws {
        let result = sqlite3_open(self.dbPath, &self.db)
        guard result == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(self.db))
            throw UsageHistoryError.openFailed(errorMessage)
        }

        sqlite3_exec(self.db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(self.db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
    }

    private func createTables() throws {
        let createSQL = """
            CREATE TABLE IF NOT EXISTS usage_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                primary_used_percent REAL,
                primary_window_minutes INTEGER,
                primary_resets_at INTEGER,
                primary_reset_desc TEXT,
                secondary_used_percent REAL,
                secondary_window_minutes INTEGER,
                secondary_resets_at INTEGER,
                secondary_reset_desc TEXT,
                tertiary_used_percent REAL,
                tertiary_window_minutes INTEGER,
                account_email TEXT,
                account_plan TEXT,
                version TEXT,
                source_label TEXT,
                credits_remaining REAL,
                raw_json TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_usage_provider_timestamp
                ON usage_history(provider, timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_usage_timestamp
                ON usage_history(timestamp DESC);

            CREATE TABLE IF NOT EXISTS cost_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                session_tokens INTEGER,
                session_cost_usd REAL,
                period_tokens INTEGER,
                period_cost_usd REAL,
                period_days INTEGER,
                models_used TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_cost_provider_timestamp
                ON cost_history(provider, timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_cost_timestamp
                ON cost_history(timestamp DESC);

            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            );
            """

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(self.db, createSQL, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw UsageHistoryError.createTableFailed(message)
        }
    }

    private func migrateIfNeeded() throws {
        let currentVersion = self.getSchemaVersion()
        if currentVersion < Self.schemaVersion {
            try self.migrate(from: currentVersion, to: Self.schemaVersion)
            self.setSchemaVersion(Self.schemaVersion)
        }
    }

    private func getSchemaVersion() -> Int {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM metadata WHERE key = 'schema_version'"
        guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) {
            return Int(String(cString: text)) ?? 0
        }
        return 0
    }

    private func setSchemaVersion(_ version: Int) {
        let sql = "INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, String(version), -1, Self.SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    private func migrate(from oldVersion: Int, to newVersion: Int) throws {
        // Migration from v1 to v2: add new columns
        if oldVersion < 2 {
            let alterSQL = """
                ALTER TABLE usage_history ADD COLUMN primary_reset_desc TEXT;
                ALTER TABLE usage_history ADD COLUMN secondary_reset_desc TEXT;
                ALTER TABLE usage_history ADD COLUMN version TEXT;
                ALTER TABLE usage_history ADD COLUMN source_label TEXT;
                ALTER TABLE usage_history ADD COLUMN credits_remaining REAL;
                """
            // Execute each ALTER separately (SQLite doesn't support multiple ALTERs in one exec)
            for statement in alterSQL.split(separator: ";") {
                let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                sqlite3_exec(self.db, trimmed + ";", nil, nil, nil)
            }
        }

        // Migration from v2 to v3: add cost_history table
        if oldVersion < 3 {
            let createCostSQL = """
                CREATE TABLE IF NOT EXISTS cost_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    provider TEXT NOT NULL,
                    timestamp INTEGER NOT NULL,
                    session_tokens INTEGER,
                    session_cost_usd REAL,
                    period_tokens INTEGER,
                    period_cost_usd REAL,
                    period_days INTEGER,
                    models_used TEXT
                );

                CREATE INDEX IF NOT EXISTS idx_cost_provider_timestamp
                    ON cost_history(provider, timestamp DESC);

                CREATE INDEX IF NOT EXISTS idx_cost_timestamp
                    ON cost_history(timestamp DESC);
                """
            for statement in createCostSQL.split(separator: ";") {
                let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                sqlite3_exec(self.db, trimmed + ";", nil, nil, nil)
            }
        }
    }

    // MARK: - Insert from CLI Payload

    /// Insert usage data from CodexBarCLI JSON output
    public func insertFromCLIPayload(_ payload: CLIProviderPayload) throws {
        let record = UsageHistoryRecord(
            provider: payload.provider,
            timestamp: payload.usage.updatedAt,
            primaryUsedPercent: payload.usage.primary?.usedPercent,
            primaryWindowMinutes: payload.usage.primary?.windowMinutes,
            primaryResetsAt: payload.usage.primary?.resetsAt,
            primaryResetDesc: payload.usage.primary?.resetDescription,
            secondaryUsedPercent: payload.usage.secondary?.usedPercent,
            secondaryWindowMinutes: payload.usage.secondary?.windowMinutes,
            secondaryResetsAt: payload.usage.secondary?.resetsAt,
            secondaryResetDesc: payload.usage.secondary?.resetDescription,
            tertiaryUsedPercent: payload.usage.tertiary?.usedPercent,
            tertiaryWindowMinutes: payload.usage.tertiary?.windowMinutes,
            accountEmail: payload.usage.identity?.accountEmail ?? payload.usage.accountEmail,
            accountPlan: payload.usage.identity?.loginMethod ?? payload.usage.loginMethod,
            version: payload.version,
            sourceLabel: payload.source,
            creditsRemaining: payload.credits?.remaining,
            rawJSON: nil
        )
        try self.insert(record)
    }

    /// Insert multiple CLI payloads
    public func insertFromCLIPayloads(_ payloads: [CLIProviderPayload]) throws {
        for payload in payloads {
            try self.insertFromCLIPayload(payload)
        }
    }

    // MARK: - Insert Records

    /// Insert a usage snapshot into the history
    public func insert(_ snapshot: UsageSnapshot, provider: UsageProvider, source: String? = nil) throws {
        try self.queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let rawJSON = try? encoder.encode(snapshot)
            let rawJSONString = rawJSON.flatMap { String(data: $0, encoding: .utf8) }

            let sql = """
                INSERT INTO usage_history (
                    provider, timestamp,
                    primary_used_percent, primary_window_minutes, primary_resets_at, primary_reset_desc,
                    secondary_used_percent, secondary_window_minutes, secondary_resets_at, secondary_reset_desc,
                    tertiary_used_percent, tertiary_window_minutes,
                    account_email, account_plan, version, source_label, credits_remaining, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, provider.rawValue, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(snapshot.updatedAt.timeIntervalSince1970))

            self.bindOptionalDouble(stmt, 3, snapshot.primary?.usedPercent)
            self.bindOptionalInt(stmt, 4, snapshot.primary?.windowMinutes)
            self.bindOptionalDate(stmt, 5, snapshot.primary?.resetsAt)
            self.bindOptionalText(stmt, 6, snapshot.primary?.resetDescription)

            self.bindOptionalDouble(stmt, 7, snapshot.secondary?.usedPercent)
            self.bindOptionalInt(stmt, 8, snapshot.secondary?.windowMinutes)
            self.bindOptionalDate(stmt, 9, snapshot.secondary?.resetsAt)
            self.bindOptionalText(stmt, 10, snapshot.secondary?.resetDescription)

            self.bindOptionalDouble(stmt, 11, snapshot.tertiary?.usedPercent)
            self.bindOptionalInt(stmt, 12, snapshot.tertiary?.windowMinutes)

            self.bindOptionalText(stmt, 13, snapshot.identity?.accountEmail)
            self.bindOptionalText(stmt, 14, snapshot.identity?.loginMethod)
            self.bindOptionalText(stmt, 15, nil) // version
            self.bindOptionalText(stmt, 16, source)
            self.bindOptionalDouble(stmt, 17, nil) // credits
            self.bindOptionalText(stmt, 18, rawJSONString)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageHistoryError.insertFailed(self.lastErrorMessage())
            }
        }
    }

    /// Insert a raw record
    public func insert(_ record: UsageHistoryRecord) throws {
        try self.queue.sync {
            let sql = """
                INSERT INTO usage_history (
                    provider, timestamp,
                    primary_used_percent, primary_window_minutes, primary_resets_at, primary_reset_desc,
                    secondary_used_percent, secondary_window_minutes, secondary_resets_at, secondary_reset_desc,
                    tertiary_used_percent, tertiary_window_minutes,
                    account_email, account_plan, version, source_label, credits_remaining, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, record.provider, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(record.timestamp.timeIntervalSince1970))

            self.bindOptionalDouble(stmt, 3, record.primaryUsedPercent)
            self.bindOptionalInt(stmt, 4, record.primaryWindowMinutes)
            self.bindOptionalDate(stmt, 5, record.primaryResetsAt)
            self.bindOptionalText(stmt, 6, record.primaryResetDesc)

            self.bindOptionalDouble(stmt, 7, record.secondaryUsedPercent)
            self.bindOptionalInt(stmt, 8, record.secondaryWindowMinutes)
            self.bindOptionalDate(stmt, 9, record.secondaryResetsAt)
            self.bindOptionalText(stmt, 10, record.secondaryResetDesc)

            self.bindOptionalDouble(stmt, 11, record.tertiaryUsedPercent)
            self.bindOptionalInt(stmt, 12, record.tertiaryWindowMinutes)

            self.bindOptionalText(stmt, 13, record.accountEmail)
            self.bindOptionalText(stmt, 14, record.accountPlan)
            self.bindOptionalText(stmt, 15, record.version)
            self.bindOptionalText(stmt, 16, record.sourceLabel)
            self.bindOptionalDouble(stmt, 17, record.creditsRemaining)
            self.bindOptionalText(stmt, 18, record.rawJSON)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageHistoryError.insertFailed(self.lastErrorMessage())
            }
        }
    }

    // MARK: - Query Records

    /// Fetch recent history for a provider
    public func fetchHistory(
        provider: UsageProvider,
        limit: Int = 100,
        since: Date? = nil
    ) throws -> [UsageHistoryRecord] {
        try self.queue.sync {
            var sql = """
                SELECT id, provider, timestamp,
                       primary_used_percent, primary_window_minutes, primary_resets_at, primary_reset_desc,
                       secondary_used_percent, secondary_window_minutes, secondary_resets_at, secondary_reset_desc,
                       tertiary_used_percent, tertiary_window_minutes,
                       account_email, account_plan, version, source_label, credits_remaining, raw_json
                FROM usage_history
                WHERE provider = ?
                """

            if since != nil {
                sql += " AND timestamp >= ?"
            }
            sql += " ORDER BY timestamp DESC LIMIT ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            var paramIndex: Int32 = 1
            sqlite3_bind_text(stmt, paramIndex, provider.rawValue, -1, Self.SQLITE_TRANSIENT)
            paramIndex += 1

            if let since = since {
                sqlite3_bind_int64(stmt, paramIndex, Int64(since.timeIntervalSince1970))
                paramIndex += 1
            }
            sqlite3_bind_int(stmt, paramIndex, Int32(limit))

            var records: [UsageHistoryRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                records.append(self.readRecord(from: stmt))
            }
            return records
        }
    }

    /// Fetch history for all providers
    public func fetchAllHistory(limit: Int = 100, since: Date? = nil) throws -> [UsageHistoryRecord] {
        try self.queue.sync {
            var sql = """
                SELECT id, provider, timestamp,
                       primary_used_percent, primary_window_minutes, primary_resets_at, primary_reset_desc,
                       secondary_used_percent, secondary_window_minutes, secondary_resets_at, secondary_reset_desc,
                       tertiary_used_percent, tertiary_window_minutes,
                       account_email, account_plan, version, source_label, credits_remaining, raw_json
                FROM usage_history
                """

            if since != nil {
                sql += " WHERE timestamp >= ?"
            }
            sql += " ORDER BY timestamp DESC LIMIT ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            var paramIndex: Int32 = 1
            if let since = since {
                sqlite3_bind_int64(stmt, paramIndex, Int64(since.timeIntervalSince1970))
                paramIndex += 1
            }
            sqlite3_bind_int(stmt, paramIndex, Int32(limit))

            var records: [UsageHistoryRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                records.append(self.readRecord(from: stmt))
            }
            return records
        }
    }

    /// Get the latest record for each provider
    public func fetchLatestForAllProviders() throws -> [String: UsageHistoryRecord] {
        try self.queue.sync {
            let sql = """
                SELECT h.id, h.provider, h.timestamp,
                       h.primary_used_percent, h.primary_window_minutes, h.primary_resets_at, h.primary_reset_desc,
                       h.secondary_used_percent, h.secondary_window_minutes, h.secondary_resets_at, h.secondary_reset_desc,
                       h.tertiary_used_percent, h.tertiary_window_minutes,
                       h.account_email, h.account_plan, h.version, h.source_label, h.credits_remaining, h.raw_json
                FROM usage_history h
                INNER JOIN (
                    SELECT provider, MAX(timestamp) as max_ts
                    FROM usage_history
                    GROUP BY provider
                ) latest ON h.provider = latest.provider AND h.timestamp = latest.max_ts
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            var result: [String: UsageHistoryRecord] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let record = self.readRecord(from: stmt)
                result[record.provider] = record
            }
            return result
        }
    }

    /// Get list of providers that have data
    public func fetchActiveProviders() throws -> [String] {
        try self.queue.sync {
            let sql = "SELECT DISTINCT provider FROM usage_history ORDER BY provider"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            var providers: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let text = sqlite3_column_text(stmt, 0) {
                    providers.append(String(cString: text))
                }
            }
            return providers
        }
    }

    // MARK: - Statistics

    /// Calculate statistics for a provider over a time period
    public func calculateStatistics(
        provider: UsageProvider,
        from startDate: Date,
        to endDate: Date
    ) throws -> UsageStatistics {
        try self.queue.sync {
            let sql = """
                SELECT
                    COUNT(*) as count,
                    AVG(primary_used_percent) as avg_primary,
                    MAX(primary_used_percent) as max_primary,
                    MIN(primary_used_percent) as min_primary,
                    AVG(secondary_used_percent) as avg_secondary,
                    MAX(secondary_used_percent) as max_secondary
                FROM usage_history
                WHERE provider = ?
                  AND timestamp >= ?
                  AND timestamp <= ?
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, provider.rawValue, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 3, Int64(endDate.timeIntervalSince1970))

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw UsageHistoryError.queryFailed(self.lastErrorMessage())
            }

            return UsageStatistics(
                provider: provider.rawValue,
                periodStart: startDate,
                periodEnd: endDate,
                recordCount: Int(sqlite3_column_int(stmt, 0)),
                avgPrimaryUsage: self.readOptionalDouble(stmt, 1),
                maxPrimaryUsage: self.readOptionalDouble(stmt, 2),
                minPrimaryUsage: self.readOptionalDouble(stmt, 3),
                avgSecondaryUsage: self.readOptionalDouble(stmt, 4),
                maxSecondaryUsage: self.readOptionalDouble(stmt, 5)
            )
        }
    }

    // MARK: - Cost History Insert

    /// Insert a cost snapshot into history
    public func insertCost(_ record: CostHistoryRecord) throws {
        try self.queue.sync {
            let sql = """
                INSERT INTO cost_history (
                    provider, timestamp, session_tokens, session_cost_usd,
                    period_tokens, period_cost_usd, period_days, models_used
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, record.provider, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(record.timestamp.timeIntervalSince1970))
            self.bindOptionalInt(stmt, 3, record.sessionTokens)
            self.bindOptionalDouble(stmt, 4, record.sessionCostUSD)
            self.bindOptionalInt(stmt, 5, record.periodTokens)
            self.bindOptionalDouble(stmt, 6, record.periodCostUSD)
            self.bindOptionalInt(stmt, 7, record.periodDays)
            self.bindOptionalText(stmt, 8, record.modelsUsed)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageHistoryError.insertFailed(self.lastErrorMessage())
            }
        }
    }

    /// Insert cost data with raw values
    public func insertCost(
        provider: String,
        timestamp: Date = Date(),
        sessionTokens: Int?,
        sessionCostUSD: Double?,
        periodTokens: Int?,
        periodCostUSD: Double?,
        periodDays: Int?,
        modelsUsed: [String]?
    ) throws {
        let modelsJSON: String?
        if let models = modelsUsed, !models.isEmpty {
            modelsJSON = try? String(data: JSONEncoder().encode(models), encoding: .utf8)
        } else {
            modelsJSON = nil
        }

        let record = CostHistoryRecord(
            provider: provider,
            timestamp: timestamp,
            sessionTokens: sessionTokens,
            sessionCostUSD: sessionCostUSD,
            periodTokens: periodTokens,
            periodCostUSD: periodCostUSD,
            periodDays: periodDays,
            modelsUsed: modelsJSON
        )
        try self.insertCost(record)
    }

    // MARK: - Cost History Query

    /// Fetch recent cost history for a provider
    public func fetchCostHistory(
        provider: String,
        limit: Int = 100,
        since: Date? = nil
    ) throws -> [CostHistoryRecord] {
        try self.queue.sync {
            var sql = """
                SELECT id, provider, timestamp, session_tokens, session_cost_usd,
                       period_tokens, period_cost_usd, period_days, models_used
                FROM cost_history
                WHERE provider = ?
                """

            if since != nil {
                sql += " AND timestamp >= ?"
            }
            sql += " ORDER BY timestamp DESC LIMIT ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            var paramIndex: Int32 = 1
            sqlite3_bind_text(stmt, paramIndex, provider, -1, Self.SQLITE_TRANSIENT)
            paramIndex += 1

            if let since = since {
                sqlite3_bind_int64(stmt, paramIndex, Int64(since.timeIntervalSince1970))
                paramIndex += 1
            }
            sqlite3_bind_int(stmt, paramIndex, Int32(limit))

            var records: [CostHistoryRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                records.append(self.readCostRecord(from: stmt))
            }
            return records
        }
    }

    /// Fetch cost history for all providers
    public func fetchAllCostHistory(limit: Int = 100, since: Date? = nil) throws -> [CostHistoryRecord] {
        try self.queue.sync {
            var sql = """
                SELECT id, provider, timestamp, session_tokens, session_cost_usd,
                       period_tokens, period_cost_usd, period_days, models_used
                FROM cost_history
                """

            if since != nil {
                sql += " WHERE timestamp >= ?"
            }
            sql += " ORDER BY timestamp DESC LIMIT ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            var paramIndex: Int32 = 1
            if let since = since {
                sqlite3_bind_int64(stmt, paramIndex, Int64(since.timeIntervalSince1970))
                paramIndex += 1
            }
            sqlite3_bind_int(stmt, paramIndex, Int32(limit))

            var records: [CostHistoryRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                records.append(self.readCostRecord(from: stmt))
            }
            return records
        }
    }

    /// Get the latest cost record for each provider
    public func fetchLatestCostForAllProviders() throws -> [String: CostHistoryRecord] {
        try self.queue.sync {
            let sql = """
                SELECT c.id, c.provider, c.timestamp, c.session_tokens, c.session_cost_usd,
                       c.period_tokens, c.period_cost_usd, c.period_days, c.models_used
                FROM cost_history c
                INNER JOIN (
                    SELECT provider, MAX(timestamp) as max_ts
                    FROM cost_history
                    GROUP BY provider
                ) latest ON c.provider = latest.provider AND c.timestamp = latest.max_ts
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            var result: [String: CostHistoryRecord] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let record = self.readCostRecord(from: stmt)
                result[record.provider] = record
            }
            return result
        }
    }

    /// Get cost record count
    public func costRecordCount() throws -> Int {
        try self.queue.sync {
            let sql = "SELECT COUNT(*) FROM cost_history"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw UsageHistoryError.queryFailed(self.lastErrorMessage())
            }

            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// Delete old cost records
    public func pruneOldCostRecords(olderThan date: Date) throws -> Int {
        try self.queue.sync {
            let sql = "DELETE FROM cost_history WHERE timestamp < ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, Int64(date.timeIntervalSince1970))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageHistoryError.deleteFailed(self.lastErrorMessage())
            }

            return Int(sqlite3_changes(self.db))
        }
    }

    /// Delete all cost records (for testing)
    public func deleteAllCostRecords() throws {
        try self.queue.sync {
            sqlite3_exec(self.db, "DELETE FROM cost_history", nil, nil, nil)
        }
    }

    private func readCostRecord(from stmt: OpaquePointer?) -> CostHistoryRecord {
        CostHistoryRecord(
            id: sqlite3_column_int64(stmt, 0),
            provider: String(cString: sqlite3_column_text(stmt, 1)),
            timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 2))),
            sessionTokens: self.readOptionalInt(stmt, 3),
            sessionCostUSD: self.readOptionalDouble(stmt, 4),
            periodTokens: self.readOptionalInt(stmt, 5),
            periodCostUSD: self.readOptionalDouble(stmt, 6),
            periodDays: self.readOptionalInt(stmt, 7),
            modelsUsed: self.readOptionalText(stmt, 8)
        )
    }

    // MARK: - Maintenance

    /// Delete records older than a certain date
    public func pruneOldRecords(olderThan date: Date) throws -> Int {
        try self.queue.sync {
            let sql = "DELETE FROM usage_history WHERE timestamp < ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, Int64(date.timeIntervalSince1970))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw UsageHistoryError.deleteFailed(self.lastErrorMessage())
            }

            return Int(sqlite3_changes(self.db))
        }
    }

    /// Delete all records (for testing)
    public func deleteAllRecords() throws {
        try self.queue.sync {
            sqlite3_exec(self.db, "DELETE FROM usage_history", nil, nil, nil)
        }
    }

    /// Get total record count
    public func recordCount() throws -> Int {
        try self.queue.sync {
            let sql = "SELECT COUNT(*) FROM usage_history"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw UsageHistoryError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw UsageHistoryError.queryFailed(self.lastErrorMessage())
            }

            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// Vacuum the database to reclaim space
    public func vacuum() throws {
        _ = self.queue.sync {
            sqlite3_exec(self.db, "VACUUM;", nil, nil, nil)
        }
    }

    // MARK: - Helpers

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(self.db))
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value = value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value = value {
            sqlite3_bind_int(stmt, index, Int32(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalDate(_ stmt: OpaquePointer?, _ index: Int32, _ value: Date?) {
        if let value = value {
            sqlite3_bind_int64(stmt, index, Int64(value.timeIntervalSince1970))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, value, -1, Self.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func readOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return sqlite3_column_double(stmt, index)
    }

    private func readOptionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return Int(sqlite3_column_int(stmt, index))
    }

    private func readOptionalDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, index)))
    }

    private func readOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func readRecord(from stmt: OpaquePointer?) -> UsageHistoryRecord {
        UsageHistoryRecord(
            id: sqlite3_column_int64(stmt, 0),
            provider: String(cString: sqlite3_column_text(stmt, 1)),
            timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 2))),
            primaryUsedPercent: self.readOptionalDouble(stmt, 3),
            primaryWindowMinutes: self.readOptionalInt(stmt, 4),
            primaryResetsAt: self.readOptionalDate(stmt, 5),
            primaryResetDesc: self.readOptionalText(stmt, 6),
            secondaryUsedPercent: self.readOptionalDouble(stmt, 7),
            secondaryWindowMinutes: self.readOptionalInt(stmt, 8),
            secondaryResetsAt: self.readOptionalDate(stmt, 9),
            secondaryResetDesc: self.readOptionalText(stmt, 10),
            tertiaryUsedPercent: self.readOptionalDouble(stmt, 11),
            tertiaryWindowMinutes: self.readOptionalInt(stmt, 12),
            accountEmail: self.readOptionalText(stmt, 13),
            accountPlan: self.readOptionalText(stmt, 14),
            version: self.readOptionalText(stmt, 15),
            sourceLabel: self.readOptionalText(stmt, 16),
            creditsRemaining: self.readOptionalDouble(stmt, 17),
            rawJSON: self.readOptionalText(stmt, 18)
        )
    }
}

// MARK: - Errors

public enum UsageHistoryError: LocalizedError, Sendable {
    case openFailed(String)
    case createTableFailed(String)
    case prepareFailed(String)
    case insertFailed(String)
    case queryFailed(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(msg): "Failed to open database: \(msg)"
        case let .createTableFailed(msg): "Failed to create tables: \(msg)"
        case let .prepareFailed(msg): "Failed to prepare statement: \(msg)"
        case let .insertFailed(msg): "Failed to insert record: \(msg)"
        case let .queryFailed(msg): "Query failed: \(msg)"
        case let .deleteFailed(msg): "Failed to delete records: \(msg)"
        }
    }
}
