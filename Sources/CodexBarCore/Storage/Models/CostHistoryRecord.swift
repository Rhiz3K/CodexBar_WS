import Foundation

/// A single cost snapshot stored in the database.
public struct CostHistoryRecord: Codable, Sendable {
    public let id: Int64
    public let provider: String
    public let timestamp: Date
    public let sessionTokens: Int?
    public let sessionCostUSD: Double?
    public let periodTokens: Int?
    public let periodCostUSD: Double?
    public let periodDays: Int?
    public let modelsUsed: String? // JSON array of model names

    public init(
        id: Int64 = 0,
        provider: String,
        timestamp: Date,
        sessionTokens: Int? = nil,
        sessionCostUSD: Double? = nil,
        periodTokens: Int? = nil,
        periodCostUSD: Double? = nil,
        periodDays: Int? = nil,
        modelsUsed: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.timestamp = timestamp
        self.sessionTokens = sessionTokens
        self.sessionCostUSD = sessionCostUSD
        self.periodTokens = periodTokens
        self.periodCostUSD = periodCostUSD
        self.periodDays = periodDays
        self.modelsUsed = modelsUsed
    }

    public var models: [String] {
        guard let json = self.modelsUsed,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }
}

/// Aggregated cost statistics for a time period.
public struct CostStatistics: Codable, Sendable {
    public let provider: String
    public let periodStart: Date
    public let periodEnd: Date
    public let recordCount: Int
    public let totalCostUSD: Double?
    public let totalTokens: Int?
    public let avgDailyCostUSD: Double?
    public let maxDailyCostUSD: Double?

    public init(
        provider: String,
        periodStart: Date,
        periodEnd: Date,
        recordCount: Int,
        totalCostUSD: Double?,
        totalTokens: Int?,
        avgDailyCostUSD: Double?,
        maxDailyCostUSD: Double?
    ) {
        self.provider = provider
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.recordCount = recordCount
        self.totalCostUSD = totalCostUSD
        self.totalTokens = totalTokens
        self.avgDailyCostUSD = avgDailyCostUSD
        self.maxDailyCostUSD = maxDailyCostUSD
    }
}
