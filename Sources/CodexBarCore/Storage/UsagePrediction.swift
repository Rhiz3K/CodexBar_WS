// UsagePrediction.swift
// Linear extrapolation prediction engine for usage forecasting
// Cross-platform: macOS and Linux

import Foundation

// MARK: - Prediction Result

/// Result of a usage prediction calculation
public struct UsagePrediction: Codable, Sendable {
    /// Provider being predicted
    public let provider: String

    /// Current usage percentage
    public let currentUsage: Double

    /// Predicted usage percentage at target time
    public let predictedUsage: Double

    /// Time when prediction was calculated
    public let calculatedAt: Date

    /// Target time for prediction
    public let predictedAt: Date

    /// Estimated time to reach 100% (nil if decreasing or already at 100%)
    public let estimatedTimeToLimit: TimeInterval?

    /// Estimated date when limit will be reached
    public let estimatedLimitDate: Date?

    /// Rate of change in percent per hour
    public let ratePerHour: Double

    /// Confidence score (0-1) based on data quality
    public let confidence: Double

    /// Number of data points used for prediction
    public let dataPointCount: Int

    /// Time span of data used (in seconds)
    public let dataTimeSpan: TimeInterval

    public init(
        provider: String,
        currentUsage: Double,
        predictedUsage: Double,
        calculatedAt: Date,
        predictedAt: Date,
        estimatedTimeToLimit: TimeInterval?,
        estimatedLimitDate: Date?,
        ratePerHour: Double,
        confidence: Double,
        dataPointCount: Int,
        dataTimeSpan: TimeInterval
    ) {
        self.provider = provider
        self.currentUsage = currentUsage
        self.predictedUsage = predictedUsage
        self.calculatedAt = calculatedAt
        self.predictedAt = predictedAt
        self.estimatedTimeToLimit = estimatedTimeToLimit
        self.estimatedLimitDate = estimatedLimitDate
        self.ratePerHour = ratePerHour
        self.confidence = confidence
        self.dataPointCount = dataPointCount
        self.dataTimeSpan = dataTimeSpan
    }

    /// Human-readable time to limit
    public var timeToLimitDescription: String? {
        guard let seconds = self.estimatedTimeToLimit, seconds > 0 else { return nil }

        let hours = Int(seconds / 3600)

        // Cap at 30 days
        if hours > 30 * 24 {
            return "30d+"
        }

        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Status indicator based on prediction
    public var status: PredictionStatus {
        if self.currentUsage >= 100 {
            return .atLimit
        }
        guard let timeToLimit = self.estimatedTimeToLimit, timeToLimit > 0 else {
            return .decreasing
        }
        let hours = timeToLimit / 3600
        if hours < 1 {
            return .critical
        } else if hours < 4 {
            return .warning
        } else {
            return .healthy
        }
    }
}

/// Status indicator for prediction health
public enum PredictionStatus: String, Codable, Sendable {
    case healthy    // > 4 hours to limit
    case warning    // 1-4 hours to limit
    case critical   // < 1 hour to limit
    case atLimit    // At or over 100%
    case decreasing // Usage is going down
}

// MARK: - Prediction Engine

/// Engine for calculating usage predictions using linear regression
public struct UsagePredictionEngine: Sendable {
    /// Minimum data points required for prediction
    public static let minimumDataPoints = 3

    /// Minimum time span (in seconds) for reliable prediction
    public static let minimumTimeSpan: TimeInterval = 300 // 5 minutes

    public init() {}

    /// Calculate prediction for a provider using historical data
    public func predict(
        records: [UsageHistoryRecord],
        forHoursAhead hours: Double = 1.0,
        usePrimary: Bool = true
    ) -> UsagePrediction? {
        // Filter records with valid usage data
        let validRecords = records.compactMap { record -> (timestamp: Date, usage: Double)? in
            let usage = usePrimary ? record.primaryUsedPercent : record.secondaryUsedPercent
            guard let usage = usage else { return nil }
            return (record.timestamp, usage)
        }.sorted { $0.timestamp < $1.timestamp }

        guard validRecords.count >= Self.minimumDataPoints else {
            return nil
        }

        guard let first = validRecords.first, let last = validRecords.last else {
            return nil
        }

        let timeSpan = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeSpan >= Self.minimumTimeSpan else {
            return nil
        }

        // Perform linear regression
        let regression = self.linearRegression(points: validRecords)

        let now = Date()
        let targetTime = now.addingTimeInterval(hours * 3600)

        // Calculate current and predicted values
        let currentUsage = regression.predict(at: now)
        let predictedUsage = regression.predict(at: targetTime)

        // Calculate time to 100% limit
        var estimatedTimeToLimit: TimeInterval?
        var estimatedLimitDate: Date?

        if regression.slope > 0 && currentUsage < 100 {
            // Usage is increasing, calculate time to limit
            let remaining = 100 - currentUsage
            let hoursToLimit = remaining / (regression.slope * 3600)
            estimatedTimeToLimit = hoursToLimit * 3600
            estimatedLimitDate = now.addingTimeInterval(estimatedTimeToLimit!)
        }

        // Calculate confidence based on data quality
        let confidence = self.calculateConfidence(
            dataPoints: validRecords.count,
            timeSpan: timeSpan,
            r2: regression.r2
        )

        return UsagePrediction(
            provider: records.first?.provider ?? "unknown",
            currentUsage: max(0, min(100, currentUsage)),
            predictedUsage: max(0, min(100, predictedUsage)),
            calculatedAt: now,
            predictedAt: targetTime,
            estimatedTimeToLimit: estimatedTimeToLimit,
            estimatedLimitDate: estimatedLimitDate,
            ratePerHour: regression.slope * 3600, // Convert to percent per hour
            confidence: confidence,
            dataPointCount: validRecords.count,
            dataTimeSpan: timeSpan
        )
    }

    /// Predict from UsageHistoryStore directly
    public func predict(
        from store: UsageHistoryStore,
        provider: UsageProvider,
        lookbackHours: Double = 24,
        forHoursAhead hours: Double = 1.0,
        usePrimary: Bool = true
    ) throws -> UsagePrediction? {
        let since = Date().addingTimeInterval(-lookbackHours * 3600)
        let records = try store.fetchHistory(provider: provider, limit: 1000, since: since)
        return self.predict(records: records, forHoursAhead: hours, usePrimary: usePrimary)
    }

    // MARK: - Linear Regression

    private struct RegressionResult {
        let slope: Double       // Change per second
        let intercept: Double   // Value at reference time
        let referenceTime: Date // Time used as origin
        let r2: Double          // R-squared (goodness of fit)

        func predict(at date: Date) -> Double {
            let seconds = date.timeIntervalSince(self.referenceTime)
            return self.intercept + self.slope * seconds
        }
    }

    private func linearRegression(points: [(timestamp: Date, usage: Double)]) -> RegressionResult {
        guard points.count >= 2 else {
            return RegressionResult(
                slope: 0,
                intercept: points.first?.usage ?? 0,
                referenceTime: points.first?.timestamp ?? Date(),
                r2: 0
            )
        }

        let referenceTime = points.first!.timestamp

        // Convert to (x, y) where x is seconds from reference
        let xyPoints = points.map { point -> (x: Double, y: Double) in
            (point.timestamp.timeIntervalSince(referenceTime), point.usage)
        }

        let n = Double(xyPoints.count)
        let sumX = xyPoints.reduce(0) { $0 + $1.x }
        let sumY = xyPoints.reduce(0) { $0 + $1.y }
        let sumXY = xyPoints.reduce(0) { $0 + $1.x * $1.y }
        let sumX2 = xyPoints.reduce(0) { $0 + $1.x * $1.x }
        let sumY2 = xyPoints.reduce(0) { $0 + $1.y * $1.y }

        let meanX = sumX / n
        let meanY = sumY / n

        let denominator = sumX2 - sumX * sumX / n
        guard denominator != 0 else {
            return RegressionResult(
                slope: 0,
                intercept: meanY,
                referenceTime: referenceTime,
                r2: 0
            )
        }

        let slope = (sumXY - sumX * sumY / n) / denominator
        let intercept = meanY - slope * meanX

        // Calculate R-squared
        let ssTotal = sumY2 - sumY * sumY / n
        var ssResidual = 0.0
        for point in xyPoints {
            let predicted = intercept + slope * point.x
            ssResidual += (point.y - predicted) * (point.y - predicted)
        }
        let r2 = ssTotal > 0 ? 1 - ssResidual / ssTotal : 0

        return RegressionResult(
            slope: slope,
            intercept: intercept,
            referenceTime: referenceTime,
            r2: max(0, min(1, r2))
        )
    }

    // MARK: - Confidence Calculation

    private func calculateConfidence(dataPoints: Int, timeSpan: TimeInterval, r2: Double) -> Double {
        // Factor 1: Number of data points (more = better)
        let pointsFactor: Double
        if dataPoints >= 50 {
            pointsFactor = 1.0
        } else if dataPoints >= 20 {
            pointsFactor = 0.8
        } else if dataPoints >= 10 {
            pointsFactor = 0.6
        } else {
            pointsFactor = 0.4
        }

        // Factor 2: Time span (longer = better for trend detection)
        let hourSpan = timeSpan / 3600
        let timeFactor: Double
        if hourSpan >= 12 {
            timeFactor = 1.0
        } else if hourSpan >= 4 {
            timeFactor = 0.8
        } else if hourSpan >= 1 {
            timeFactor = 0.6
        } else {
            timeFactor = 0.4
        }

        // Factor 3: R-squared (how well data fits the line)
        let fitFactor = r2

        // Weighted average
        return (pointsFactor * 0.3 + timeFactor * 0.3 + fitFactor * 0.4)
    }
}

// MARK: - Provider Predictions (Primary + Secondary)

/// Combined predictions for a provider (session + weekly)
public struct ProviderPredictions: Sendable {
    public let provider: String
    public let primary: UsagePrediction?
    public let secondary: UsagePrediction?

    public init(provider: String, primary: UsagePrediction?, secondary: UsagePrediction?) {
        self.provider = provider
        self.primary = primary
        self.secondary = secondary
    }
}

// MARK: - Batch Predictions

extension UsagePredictionEngine {
    /// Generate predictions for both primary and secondary usage
    public func predictBoth(
        from store: UsageHistoryStore,
        provider: UsageProvider,
        lookbackHours: Double = 24,
        forHoursAhead hours: Double = 1.0
    ) throws -> ProviderPredictions {
        let primary = try self.predict(
            from: store,
            provider: provider,
            lookbackHours: lookbackHours,
            forHoursAhead: hours,
            usePrimary: true
        )
        let secondary = try self.predict(
            from: store,
            provider: provider,
            lookbackHours: lookbackHours,
            forHoursAhead: hours,
            usePrimary: false
        )
        return ProviderPredictions(provider: provider.rawValue, primary: primary, secondary: secondary)
    }

    /// Generate predictions for all providers with data
    public func predictAll(
        from store: UsageHistoryStore,
        lookbackHours: Double = 24,
        forHoursAhead hours: Double = 1.0
    ) throws -> [UsagePrediction] {
        var predictions: [UsagePrediction] = []

        for provider in UsageProvider.allCases {
            if let prediction = try self.predict(
                from: store,
                provider: provider,
                lookbackHours: lookbackHours,
                forHoursAhead: hours
            ) {
                predictions.append(prediction)
            }
        }

        return predictions
    }

    /// Generate both primary and secondary predictions for all providers
    public func predictAllBoth(
        from store: UsageHistoryStore,
        lookbackHours: Double = 24,
        forHoursAhead hours: Double = 1.0
    ) throws -> [String: ProviderPredictions] {
        var predictions: [String: ProviderPredictions] = [:]

        let activeProviders = try store.fetchActiveProviders()
        for providerName in activeProviders {
            guard let provider = UsageProvider(rawValue: providerName) else { continue }
            let pred = try self.predictBoth(
                from: store,
                provider: provider,
                lookbackHours: lookbackHours,
                forHoursAhead: hours
            )
            predictions[providerName] = pred
        }

        return predictions
    }
}
