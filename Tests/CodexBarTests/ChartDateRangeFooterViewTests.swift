import Foundation
import Testing
@testable import CodexBar

@Suite
struct ChartDateRangeFooterViewTests {
    @Test
    func shouldIncludeYear_sameYear_returnsFalse() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12)))

        #expect(
            ChartDateRangeFooterView.shouldIncludeYear(
                startDate: start,
                endDate: end,
                calendar: calendar) == false)
    }

    @Test
    func shouldIncludeYear_differentYear_returnsTrue() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let start = try #require(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 12)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)))

        #expect(
            ChartDateRangeFooterView.shouldIncludeYear(
                startDate: start,
                endDate: end,
                calendar: calendar))
    }
}
