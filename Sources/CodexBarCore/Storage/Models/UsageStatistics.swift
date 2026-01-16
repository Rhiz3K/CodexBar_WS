import Foundation

/// Aggregated usage statistics for a time period.
public struct UsageStatistics: Codable, Sendable {
    public let provider: String
    public let periodStart: Date
    public let periodEnd: Date
    public let recordCount: Int
    public let avgPrimaryUsage: Double?
    public let maxPrimaryUsage: Double?
    public let minPrimaryUsage: Double?
    public let avgSecondaryUsage: Double?
    public let maxSecondaryUsage: Double?

    public init(
        provider: String,
        periodStart: Date,
        periodEnd: Date,
        recordCount: Int,
        avgPrimaryUsage: Double?,
        maxPrimaryUsage: Double?,
        minPrimaryUsage: Double?,
        avgSecondaryUsage: Double?,
        maxSecondaryUsage: Double?
    ) {
        self.provider = provider
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.recordCount = recordCount
        self.avgPrimaryUsage = avgPrimaryUsage
        self.maxPrimaryUsage = maxPrimaryUsage
        self.minPrimaryUsage = minPrimaryUsage
        self.avgSecondaryUsage = avgSecondaryUsage
        self.maxSecondaryUsage = maxSecondaryUsage
    }
}
