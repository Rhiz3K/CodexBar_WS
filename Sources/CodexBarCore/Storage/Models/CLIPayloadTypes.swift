import Foundation

/// Types for parsing `CodexBarCLI` JSON output.
public struct CLIProviderPayload: Codable, Sendable {
    public let provider: String
    public let account: String?
    public let version: String?
    public let source: String
    public let usage: CLIUsageSnapshot
    public let credits: CLICreditsSnapshot?

    public init(
        provider: String,
        account: String? = nil,
        version: String? = nil,
        source: String,
        usage: CLIUsageSnapshot,
        credits: CLICreditsSnapshot? = nil
    ) {
        self.provider = provider
        self.account = account
        self.version = version
        self.source = source
        self.usage = usage
        self.credits = credits
    }
}

public struct CLIUsageSnapshot: Codable, Sendable {
    public let primary: CLIRateWindow?
    public let secondary: CLIRateWindow?
    public let tertiary: CLIRateWindow?
    public let updatedAt: Date
    public let identity: CLIIdentity?
    public let accountEmail: String?
    public let loginMethod: String?

    public init(
        primary: CLIRateWindow? = nil,
        secondary: CLIRateWindow? = nil,
        tertiary: CLIRateWindow? = nil,
        updatedAt: Date,
        identity: CLIIdentity? = nil,
        accountEmail: String? = nil,
        loginMethod: String? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.updatedAt = updatedAt
        self.identity = identity
        self.accountEmail = accountEmail
        self.loginMethod = loginMethod
    }
}

public struct CLIRateWindow: Codable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?

    public init(
        usedPercent: Double,
        windowMinutes: Int? = nil,
        resetsAt: Date? = nil,
        resetDescription: String? = nil
    ) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }
}

public struct CLIIdentity: Codable, Sendable {
    public let providerID: String?
    public let accountEmail: String?
    public let accountOrganization: String?
    public let loginMethod: String?

    public init(
        providerID: String? = nil,
        accountEmail: String? = nil,
        accountOrganization: String? = nil,
        loginMethod: String? = nil
    ) {
        self.providerID = providerID
        self.accountEmail = accountEmail
        self.accountOrganization = accountOrganization
        self.loginMethod = loginMethod
    }
}

public struct CLICreditsSnapshot: Codable, Sendable {
    public let remaining: Double
    public let updatedAt: Date?

    public init(remaining: Double, updatedAt: Date? = nil) {
        self.remaining = remaining
        self.updatedAt = updatedAt
    }
}
