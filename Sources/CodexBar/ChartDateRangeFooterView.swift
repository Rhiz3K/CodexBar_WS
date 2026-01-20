import Foundation
import SwiftUI

@MainActor
struct ChartDateRangeFooterView: View {
    let startDate: Date
    let endDate: Date

    var body: some View {
        let includeYear = Self.shouldIncludeYear(startDate: self.startDate, endDate: self.endDate)
        HStack {
            Text(Self.label(for: self.startDate, includeYear: includeYear))
            Spacer(minLength: 0)
            Text(Self.label(for: self.endDate, includeYear: includeYear))
        }
        .font(.caption2)
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    static func label(for date: Date, includeYear: Bool) -> String {
        if includeYear {
            return date.formatted(.dateTime.year().month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func shouldIncludeYear(startDate: Date, endDate: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.year, from: startDate) != calendar.component(.year, from: endDate)
    }
}
