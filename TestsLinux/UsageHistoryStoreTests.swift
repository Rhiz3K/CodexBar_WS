import CodexBarCore
import Foundation
import Testing

@Suite
struct UsageHistoryStoreTests {
    // Create a temporary database for each test
    func createTempStore() throws -> UsageHistoryStore {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite").path
        return try UsageHistoryStore(path: dbPath)
    }

    // Helper to create a simple record
    func makeRecord(
        provider: String,
        timestamp: Date,
        primaryUsedPercent: Double? = nil
    ) -> UsageHistoryRecord {
        UsageHistoryRecord(
            provider: provider,
            timestamp: timestamp,
            primaryUsedPercent: primaryUsedPercent
        )
    }

    // MARK: - Basic Operations

    @Test
    func insert_andFetchLatest() throws {
        let store = try self.createTempStore()

        let record = UsageHistoryRecord(
            provider: "codex",
            timestamp: Date(),
            primaryUsedPercent: 50,
            primaryResetsAt: Date().addingTimeInterval(5 * 3600),
            primaryResetDesc: "Resets in 5h",
            secondaryUsedPercent: 25,
            secondaryResetsAt: Date().addingTimeInterval(3 * 24 * 3600),
            secondaryResetDesc: "Resets in 3d",
            tertiaryUsedPercent: nil,
            accountEmail: "test@example.com",
            accountPlan: "Pro",
            version: "1.0.0",
            sourceLabel: "cli",
            creditsRemaining: 100
        )

        try store.insert(record)

        let history = try store.fetchHistory(provider: .codex, limit: 1)
        #expect(history.count == 1)
        let latest = history.first!
        #expect(latest.provider == "codex")
        #expect(latest.primaryUsedPercent == 50)
        #expect(latest.secondaryUsedPercent == 25)
        #expect(latest.accountEmail == "test@example.com")
        #expect(latest.accountPlan == "Pro")
    }

    @Test
    func fetchHistory_returnsRecordsInDescendingOrder() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert records at different times
        for i in 0 ..< 5 {
            let record = self.makeRecord(
                provider: "claude",
                timestamp: now.addingTimeInterval(Double(i) * 600),
                primaryUsedPercent: Double(50 + i * 10)
            )
            try store.insert(record)
        }

        let history = try store.fetchHistory(provider: .claude, limit: 10)

        #expect(history.count == 5)
        // Should be descending order (newest first)
        #expect(history[0].primaryUsedPercent! > history[4].primaryUsedPercent!)
    }

    @Test
    func fetchHistory_respectsLimit() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert 10 records
        for i in 0 ..< 10 {
            let record = self.makeRecord(
                provider: "gemini",
                timestamp: now.addingTimeInterval(Double(i) * 60),
                primaryUsedPercent: Double(i * 10)
            )
            try store.insert(record)
        }

        let history = try store.fetchHistory(provider: .gemini, limit: 5)
        #expect(history.count == 5)
    }

    @Test
    func fetchHistory_respectsSinceDate() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert records spanning 2 hours (older records first)
        for i in 0 ..< 12 {
            let record = self.makeRecord(
                provider: "codex",
                timestamp: now.addingTimeInterval(Double(i) * 600 - 7200), // -2h to -10min
                primaryUsedPercent: Double(i * 5)
            )
            try store.insert(record)
        }

        // Only get records from last 30 minutes (should exclude most)
        let since = now.addingTimeInterval(-1800)
        let history = try store.fetchHistory(provider: .codex, limit: 100, since: since)

        // Should have fewer records than total (only recent ones)
        #expect(history.count < 12)
        #expect(history.count >= 0)
    }

    @Test
    func fetchLatestForAllProviders_returnsAllProviders() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert records for multiple providers
        let providers: [UsageProvider] = [.codex, .claude, .gemini]
        for provider in providers {
            let record = self.makeRecord(
                provider: provider.rawValue,
                timestamp: now,
                primaryUsedPercent: 50
            )
            try store.insert(record)
        }

        let latest = try store.fetchLatestForAllProviders()

        #expect(latest.count == 3)
        #expect(latest.keys.contains("codex"))
        #expect(latest.keys.contains("claude"))
        #expect(latest.keys.contains("gemini"))
    }

    @Test
    func recordCount_returnsCorrectCount() throws {
        let store = try self.createTempStore()

        #expect(try store.recordCount() == 0)

        for i in 0 ..< 5 {
            let record = self.makeRecord(
                provider: "codex",
                timestamp: Date().addingTimeInterval(Double(i)),
                primaryUsedPercent: Double(i * 10)
            )
            try store.insert(record)
        }

        #expect(try store.recordCount() == 5)
    }

    @Test
    func fetchActiveProviders_returnsOnlyProvidersWithData() throws {
        let store = try self.createTempStore()

        // Insert records for only 2 providers
        for provider in ["codex", "claude"] {
            let record = self.makeRecord(
                provider: provider,
                timestamp: Date(),
                primaryUsedPercent: 50
            )
            try store.insert(record)
        }

        let activeProviders = try store.fetchActiveProviders()

        #expect(activeProviders.count == 2)
        #expect(activeProviders.contains("codex"))
        #expect(activeProviders.contains("claude"))
        #expect(!activeProviders.contains("gemini"))
    }

    // MARK: - Statistics

    @Test
    func calculateStatistics_computesCorrectly() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert records with known values
        let usages = [20.0, 40.0, 60.0, 80.0, 100.0]
        for (i, usage) in usages.enumerated() {
            let record = self.makeRecord(
                provider: "codex",
                timestamp: now.addingTimeInterval(Double(i) * 600),
                primaryUsedPercent: usage
            )
            try store.insert(record)
        }

        let stats = try store.calculateStatistics(
            provider: .codex,
            from: now.addingTimeInterval(-100),
            to: now.addingTimeInterval(3600)
        )

        #expect(stats.recordCount == 5)
        #expect(stats.minPrimaryUsage == 20)
        #expect(stats.maxPrimaryUsage == 100)
        #expect(stats.avgPrimaryUsage == 60) // (20+40+60+80+100)/5 = 60
    }

    // MARK: - CLI Payload Integration

    @Test
    func insertFromCLIPayload_worksCorrectly() throws {
        let store = try self.createTempStore()

        let payload = CLIProviderPayload(
            provider: "codex",
            version: "1.0.0",
            source: "cli",
            usage: CLIUsageSnapshot(
                primary: CLIRateWindow(
                    usedPercent: 75,
                    windowMinutes: 300,
                    resetsAt: Date().addingTimeInterval(3600),
                    resetDescription: "Resets in 1h"
                ),
                secondary: CLIRateWindow(
                    usedPercent: 30,
                    windowMinutes: 10080,
                    resetsAt: Date().addingTimeInterval(3 * 24 * 3600),
                    resetDescription: "Resets in 3d"
                ),
                tertiary: nil,
                updatedAt: Date(),
                identity: CLIIdentity(
                    accountEmail: "test@example.com"
                ),
                accountEmail: "test@example.com"
            ),
            credits: nil
        )

        try store.insertFromCLIPayload(payload)

        let history = try store.fetchHistory(provider: .codex, limit: 1)
        #expect(history.count == 1)
        let latest = history.first!
        #expect(latest.primaryUsedPercent == 75)
        #expect(latest.secondaryUsedPercent == 30)
        #expect(latest.accountEmail == "test@example.com")
        #expect(latest.version == "1.0.0")
        #expect(latest.sourceLabel == "cli")
    }

    // MARK: - Cost History Tests

    @Test
    func insertCost_andFetchCostHistory() throws {
        let store = try self.createTempStore()
        let now = Date()

        try store.insertCost(
            provider: "claude",
            timestamp: now,
            sessionTokens: 1_000_000,
            sessionCostUSD: 15.50,
            periodTokens: 10_000_000,
            periodCostUSD: 150.00,
            periodDays: 30,
            modelsUsed: ["claude-sonnet-4", "claude-opus-4"]
        )

        let history = try store.fetchCostHistory(provider: "claude", limit: 1)
        #expect(history.count == 1)

        let latest = history.first!
        #expect(latest.provider == "claude")
        #expect(latest.sessionTokens == 1_000_000)
        #expect(latest.sessionCostUSD == 15.50)
        #expect(latest.periodTokens == 10_000_000)
        #expect(latest.periodCostUSD == 150.00)
        #expect(latest.periodDays == 30)
        #expect(Set(latest.models) == Set(["claude-opus-4", "claude-sonnet-4"]))
    }

    @Test
    func fetchCostHistory_returnsDescendingOrder() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert records at different times
        for i in 0 ..< 5 {
            try store.insertCost(
                provider: "codex",
                timestamp: now.addingTimeInterval(Double(i) * 600),
                sessionTokens: 100_000 * (i + 1),
                sessionCostUSD: Double(i + 1) * 5.0,
                periodTokens: nil,
                periodCostUSD: nil,
                periodDays: nil,
                modelsUsed: nil
            )
        }

        let history = try store.fetchCostHistory(provider: "codex", limit: 10)

        #expect(history.count == 5)
        // Should be descending order (newest first)
        #expect(history[0].sessionTokens! > history[4].sessionTokens!)
    }

    @Test
    func fetchCostHistory_respectsLimit() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert 10 records
        for i in 0 ..< 10 {
            try store.insertCost(
                provider: "claude",
                timestamp: now.addingTimeInterval(Double(i) * 60),
                sessionTokens: i * 1000,
                sessionCostUSD: Double(i),
                periodTokens: nil,
                periodCostUSD: nil,
                periodDays: nil,
                modelsUsed: nil
            )
        }

        let history = try store.fetchCostHistory(provider: "claude", limit: 5)
        #expect(history.count == 5)
    }

    @Test
    func fetchCostHistory_respectsSinceDate() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert records spanning 2 hours (older records first)
        for i in 0 ..< 12 {
            try store.insertCost(
                provider: "codex",
                timestamp: now.addingTimeInterval(Double(i) * 600 - 7200), // -2h to -10min
                sessionTokens: i * 1000,
                sessionCostUSD: Double(i),
                periodTokens: nil,
                periodCostUSD: nil,
                periodDays: nil,
                modelsUsed: nil
            )
        }

        // Only get records from last 30 minutes
        let since = now.addingTimeInterval(-1800)
        let history = try store.fetchCostHistory(provider: "codex", limit: 100, since: since)

        // Should have fewer records than total
        #expect(history.count < 12)
    }

    @Test
    func fetchLatestCostForAllProviders_returnsAllProviders() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert cost records for multiple providers
        let providers = ["codex", "claude", "gemini"]
        for provider in providers {
            try store.insertCost(
                provider: provider,
                timestamp: now,
                sessionTokens: 100_000,
                sessionCostUSD: 10.0,
                periodTokens: 1_000_000,
                periodCostUSD: 100.0,
                periodDays: 30,
                modelsUsed: ["model-1"]
            )
        }

        let latest = try store.fetchLatestCostForAllProviders()

        #expect(latest.count == 3)
        #expect(latest.keys.contains("codex"))
        #expect(latest.keys.contains("claude"))
        #expect(latest.keys.contains("gemini"))
    }

    @Test
    func costRecordCount_returnsCorrectCount() throws {
        let store = try self.createTempStore()

        #expect(try store.costRecordCount() == 0)

        for i in 0 ..< 5 {
            try store.insertCost(
                provider: "codex",
                timestamp: Date().addingTimeInterval(Double(i)),
                sessionTokens: i * 1000,
                sessionCostUSD: Double(i),
                periodTokens: nil,
                periodCostUSD: nil,
                periodDays: nil,
                modelsUsed: nil
            )
        }

        #expect(try store.costRecordCount() == 5)
    }

    @Test
    func fetchAllCostHistory_returnsMultipleProviders() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert for multiple providers
        for (i, provider) in ["codex", "claude"].enumerated() {
            try store.insertCost(
                provider: provider,
                timestamp: now.addingTimeInterval(Double(i) * 60),
                sessionTokens: (i + 1) * 100_000,
                sessionCostUSD: Double(i + 1) * 10.0,
                periodTokens: nil,
                periodCostUSD: nil,
                periodDays: nil,
                modelsUsed: nil
            )
        }

        let history = try store.fetchAllCostHistory(limit: 10)

        #expect(history.count == 2)
        let providers = Set(history.map(\.provider))
        #expect(providers.contains("codex"))
        #expect(providers.contains("claude"))
    }

    @Test
    func costHistoryRecord_modelsParsingWorksCorrectly() throws {
        let store = try self.createTempStore()

        // Test with models
        try store.insertCost(
            provider: "claude",
            timestamp: Date(),
            sessionTokens: 100_000,
            sessionCostUSD: 10.0,
            periodTokens: nil,
            periodCostUSD: nil,
            periodDays: nil,
            modelsUsed: ["model-a", "model-b", "model-c"]
        )

        let history = try store.fetchCostHistory(provider: "claude", limit: 1)
        let record = history.first!

        #expect(record.models.count == 3)
        #expect(record.models.contains("model-a"))
        #expect(record.models.contains("model-b"))
        #expect(record.models.contains("model-c"))
    }

    @Test
    func costHistoryRecord_nilModelsReturnsEmptyArray() throws {
        let store = try self.createTempStore()

        // Test without models
        try store.insertCost(
            provider: "gemini",
            timestamp: Date(),
            sessionTokens: 50_000,
            sessionCostUSD: 5.0,
            periodTokens: nil,
            periodCostUSD: nil,
            periodDays: nil,
            modelsUsed: nil
        )

        let history = try store.fetchCostHistory(provider: "gemini", limit: 1)
        let record = history.first!

        #expect(record.models.isEmpty)
    }

    @Test
    func pruneOldCostRecords_deletesOldRecords() throws {
        let store = try self.createTempStore()
        let now = Date()

        // Insert old and new records
        try store.insertCost(
            provider: "codex",
            timestamp: now.addingTimeInterval(-7 * 24 * 3600), // 7 days ago
            sessionTokens: 100_000,
            sessionCostUSD: 10.0,
            periodTokens: nil,
            periodCostUSD: nil,
            periodDays: nil,
            modelsUsed: nil
        )

        try store.insertCost(
            provider: "codex",
            timestamp: now, // Now
            sessionTokens: 200_000,
            sessionCostUSD: 20.0,
            periodTokens: nil,
            periodCostUSD: nil,
            periodDays: nil,
            modelsUsed: nil
        )

        #expect(try store.costRecordCount() == 2)

        // Prune records older than 3 days
        let cutoff = now.addingTimeInterval(-3 * 24 * 3600)
        let deleted = try store.pruneOldCostRecords(olderThan: cutoff)

        #expect(deleted == 1)
        #expect(try store.costRecordCount() == 1)

        // Verify the recent record remains
        let history = try store.fetchCostHistory(provider: "codex", limit: 10)
        #expect(history.count == 1)
        #expect(history.first?.sessionTokens == 200_000)
    }

    @Test
    func deleteAllCostRecords_clearsAllRecords() throws {
        let store = try self.createTempStore()

        // Insert some records
        for i in 0 ..< 5 {
            try store.insertCost(
                provider: "claude",
                timestamp: Date().addingTimeInterval(Double(i)),
                sessionTokens: i * 1000,
                sessionCostUSD: Double(i),
                periodTokens: nil,
                periodCostUSD: nil,
                periodDays: nil,
                modelsUsed: nil
            )
        }

        #expect(try store.costRecordCount() == 5)

        try store.deleteAllCostRecords()

        #expect(try store.costRecordCount() == 0)
    }
}
