import Foundation

/// A single usage snapshot stored in the database.
public struct UsageHistoryRecord: Codable, Sendable {
    public let id: Int64
    public let provider: String
    public let timestamp: Date
    public let primaryUsedPercent: Double?
    public let primaryWindowMinutes: Int?
    public let primaryResetsAt: Date?
    public let primaryResetDesc: String?
    public let secondaryUsedPercent: Double?
    public let secondaryWindowMinutes: Int?
    public let secondaryResetsAt: Date?
    public let secondaryResetDesc: String?
    public let tertiaryUsedPercent: Double?
    public let tertiaryWindowMinutes: Int?
    public let accountEmail: String?
    public let accountPlan: String?
    public let version: String?
    public let sourceLabel: String?
    public let creditsRemaining: Double?
    public let rawJSON: String?

    public init(
        id: Int64 = 0,
        provider: String,
        timestamp: Date,
        primaryUsedPercent: Double? = nil,
        primaryWindowMinutes: Int? = nil,
        primaryResetsAt: Date? = nil,
        primaryResetDesc: String? = nil,
        secondaryUsedPercent: Double? = nil,
        secondaryWindowMinutes: Int? = nil,
        secondaryResetsAt: Date? = nil,
        secondaryResetDesc: String? = nil,
        tertiaryUsedPercent: Double? = nil,
        tertiaryWindowMinutes: Int? = nil,
        accountEmail: String? = nil,
        accountPlan: String? = nil,
        version: String? = nil,
        sourceLabel: String? = nil,
        creditsRemaining: Double? = nil,
        rawJSON: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.timestamp = timestamp
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.primaryResetsAt = primaryResetsAt
        self.primaryResetDesc = primaryResetDesc
        self.secondaryUsedPercent = secondaryUsedPercent
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.secondaryResetsAt = secondaryResetsAt
        self.secondaryResetDesc = secondaryResetDesc
        self.tertiaryUsedPercent = tertiaryUsedPercent
        self.tertiaryWindowMinutes = tertiaryWindowMinutes
        self.accountEmail = accountEmail
        self.accountPlan = accountPlan
        self.version = version
        self.sourceLabel = sourceLabel
        self.creditsRemaining = creditsRemaining
        self.rawJSON = rawJSON
    }
}
