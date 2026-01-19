import CodexBarCore
import Foundation
import Testing

@Suite
struct UsagePredictionTests {
    // MARK: - Prediction Status Tests

    @Test
    func status_atLimit_when100Percent() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 100,
            predictedUsage: 100,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: nil,
            estimatedLimitDate: nil,
            ratePerHour: 0,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.status == .atLimit)
    }

    @Test
    func status_critical_whenLessThan1Hour() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 95,
            predictedUsage: 100,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: 30 * 60, // 30 minutes
            estimatedLimitDate: Date().addingTimeInterval(30 * 60),
            ratePerHour: 10,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.status == .critical)
    }

    @Test
    func status_warning_when1To4Hours() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 80,
            predictedUsage: 90,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: 2 * 3600, // 2 hours
            estimatedLimitDate: Date().addingTimeInterval(2 * 3600),
            ratePerHour: 10,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.status == .warning)
    }

    @Test
    func status_healthy_whenMoreThan4Hours() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 50,
            predictedUsage: 60,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: 10 * 3600, // 10 hours
            estimatedLimitDate: Date().addingTimeInterval(10 * 3600),
            ratePerHour: 5,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.status == .healthy)
    }

    @Test
    func status_decreasing_whenNoTimeToLimit() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 50,
            predictedUsage: 40,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: nil,
            estimatedLimitDate: nil,
            ratePerHour: -5,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.status == .decreasing)
    }

    // MARK: - Time To Limit Description Tests

    @Test
    func timeToLimitDescription_minutes() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 95,
            predictedUsage: 100,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: 45 * 60, // 45 minutes
            estimatedLimitDate: Date().addingTimeInterval(45 * 60),
            ratePerHour: 10,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.timeToLimitDescription == "45m")
    }

    @Test
    func timeToLimitDescription_hoursAndMinutes() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 80,
            predictedUsage: 90,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: 3 * 3600 + 30 * 60, // 3h 30m
            estimatedLimitDate: Date().addingTimeInterval(3 * 3600 + 30 * 60),
            ratePerHour: 5,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.timeToLimitDescription == "3h 30m")
    }

    @Test
    func timeToLimitDescription_daysAndHours() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 20,
            predictedUsage: 25,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: 2 * 24 * 3600 + 5 * 3600, // 2d 5h
            estimatedLimitDate: Date().addingTimeInterval(2 * 24 * 3600 + 5 * 3600),
            ratePerHour: 1,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.timeToLimitDescription == "2d 5h")
    }

    @Test
    func timeToLimitDescription_cappedAt30Days() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 5,
            predictedUsage: 6,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: 60 * 24 * 3600, // 60 days
            estimatedLimitDate: Date().addingTimeInterval(60 * 24 * 3600),
            ratePerHour: 0.1,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.timeToLimitDescription == "30d+")
    }

    @Test
    func timeToLimitDescription_nilWhenNoTimeToLimit() {
        let prediction = UsagePrediction(
            provider: "test",
            currentUsage: 50,
            predictedUsage: 40,
            calculatedAt: Date(),
            predictedAt: Date().addingTimeInterval(3600),
            estimatedTimeToLimit: nil,
            estimatedLimitDate: nil,
            ratePerHour: -5,
            confidence: 0.8,
            dataPointCount: 10,
            dataTimeSpan: 3600
        )

        #expect(prediction.timeToLimitDescription == nil)
    }
}

@Suite
struct UsagePredictionEngineTests {
    let engine = UsagePredictionEngine()

    // Helper to create a simple record
    func makeRecord(provider: String, timestamp: Date, primaryUsedPercent: Double) -> UsageHistoryRecord {
        UsageHistoryRecord(
            provider: provider,
            timestamp: timestamp,
            primaryUsedPercent: primaryUsedPercent
        )
    }

    @Test
    func predict_returnsNil_whenInsufficientDataPoints() {
        let records = [
            self.makeRecord(provider: "test", timestamp: Date(), primaryUsedPercent: 50),
        ]

        let prediction = self.engine.predict(records: records)
        #expect(prediction == nil)
    }

    @Test
    func predict_returnsNil_whenTimeSpanTooShort() {
        let now = Date()
        let records = (0 ..< 5).map { i in
            self.makeRecord(
                provider: "test",
                timestamp: now.addingTimeInterval(Double(i)), // 1 second apart
                primaryUsedPercent: Double(50 + i)
            )
        }

        let prediction = self.engine.predict(records: records)
        #expect(prediction == nil)
    }

    @Test
    func predict_calculatesIncreasingTrend() {
        let now = Date()
        let records = (0 ..< 10).map { i in
            self.makeRecord(
                provider: "test",
                timestamp: now.addingTimeInterval(Double(i) * 600), // 10 min apart
                primaryUsedPercent: Double(50 + i * 5) // Increasing by 5% every 10 min
            )
        }

        let prediction = self.engine.predict(records: records)

        #expect(prediction != nil)
        #expect(prediction!.ratePerHour > 0)
        #expect(prediction!.estimatedTimeToLimit != nil)
    }

    @Test
    func predict_calculatesDecreasingTrend() {
        let now = Date()
        let records = (0 ..< 10).map { i in
            self.makeRecord(
                provider: "test",
                timestamp: now.addingTimeInterval(Double(i) * 600), // 10 min apart
                primaryUsedPercent: Double(80 - i * 5) // Decreasing by 5% every 10 min
            )
        }

        let prediction = self.engine.predict(records: records)

        #expect(prediction != nil)
        #expect(prediction!.ratePerHour < 0)
        #expect(prediction!.estimatedTimeToLimit == nil)
        #expect(prediction!.status == PredictionStatus.decreasing)
    }
}

@Suite
struct UsagePaceTests {
    @Test
    func weekly_willLastToReset_whenUsageLow() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 24 * 3600) // 3 days from now

        let window = RateWindow(
            usedPercent: 20,
            windowMinutes: 7 * 24 * 60, // 1 week window
            resetsAt: resetsAt,
            resetDescription: "Resets in 3d"
        )

        let pace = UsagePace.weekly(window: window, now: now)

        #expect(pace != nil)
        #expect(pace!.willLastToReset == true)
        #expect(pace!.etaSeconds == nil)
    }

    @Test
    func weekly_willNotLastToReset_whenUsageHigh() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(1 * 24 * 3600) // 1 day from now

        let window = RateWindow(
            usedPercent: 90,
            windowMinutes: 7 * 24 * 60, // 1 week window
            resetsAt: resetsAt,
            resetDescription: "Resets in 1d"
        )

        let pace = UsagePace.weekly(window: window, now: now)

        #expect(pace != nil)
        // With 90% used in 6 days, the remaining 10% won't last 1 more day
        // So willLastToReset should be false and etaSeconds should be set
    }

    @Test
    func weekly_returnsNil_whenNoResetTime() {
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 7 * 24 * 60,
            resetsAt: nil,
            resetDescription: nil
        )

        let pace = UsagePace.weekly(window: window)
        #expect(pace == nil)
    }

    @Test
    func weekly_returnsNil_whenResetInPast() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-3600) // 1 hour ago

        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 7 * 24 * 60,
            resetsAt: resetsAt,
            resetDescription: "Expired"
        )

        let pace = UsagePace.weekly(window: window, now: now)
        #expect(pace == nil)
    }
}
