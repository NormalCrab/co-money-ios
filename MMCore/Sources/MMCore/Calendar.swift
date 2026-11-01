import Foundation

/// 年月。首頁、交易列表都以「帳本時區的某個月」為單位（v2-design §2.1）。
public struct YearMonth: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "month 要在 1…12")
        self.year = year
        self.month = month
    }

    /// 某個瞬間在這個時區屬於哪個月。
    public init(_ date: Date, in timeZone: TimeZone) {
        let day = LocalDate(date, in: timeZone)
        self.init(year: day.year, month: day.month)
    }

    public var previous: YearMonth {
        month == 1 ? YearMonth(year: year - 1, month: 12) : YearMonth(year: year, month: month - 1)
    }

    public var next: YearMonth {
        month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1)
    }

    /// 這個月在這個時區的起訖瞬間（含頭不含尾）。
    public func interval(in timeZone: TimeZone) -> Range<Date> {
        let calendar = Calendar.gregorian(timeZone)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let nextMonth = next
        let end = calendar.date(from: DateComponents(year: nextMonth.year, month: nextMonth.month, day: 1))!
        return start..<end
    }

    public func contains(_ date: Date, in timeZone: TimeZone) -> Bool {
        YearMonth(date, in: timeZone) == self
    }

    /// 「2026 年 10 月」
    public var label: String { "\(year) 年 \(month) 月" }

    public var description: String { String(format: "%04d-%02d", year, month) }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// 畫面上的日期文字，例如「今天 10/27（二）」、「昨天」、「10/25（日）」。
public enum DateText {
    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    /// 交易列表的日期分組標題。
    public static func dayHeader(_ day: LocalDate, today: LocalDate) -> String {
        let base = "\(day.month)/\(day.day)（\(weekday(day))）"
        switch daysBetween(day, today) {
        case 0: return "今天 " + base
        case 1: return "昨天 " + base
        default: return day.year == today.year ? base : "\(day.year)/" + base
        }
    }

    /// 簡短的相對日期：「今天」、「昨天」、「10/25」。
    public static func shortDay(_ day: LocalDate, today: LocalDate) -> String {
        switch daysBetween(day, today) {
        case 0: "今天"
        case 1: "昨天"
        default: day.year == today.year ? "\(day.month)/\(day.day)" : "\(day.year)/\(day.month)/\(day.day)"
        }
    }

    /// 「10:42」
    public static func time(_ date: Date, in timeZone: TimeZone) -> String {
        let parts = Calendar.gregorian(timeZone).dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour!, parts.minute!)
    }

    static func weekday(_ day: LocalDate) -> String {
        let calendar = Calendar.gregorian(TimeZone(identifier: "UTC")!)
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
        return weekdays[calendar.component(.weekday, from: date) - 1]
    }

    /// `to` 比 `from` 晚幾天。
    static func daysBetween(_ from: LocalDate, _ to: LocalDate) -> Int {
        let calendar = Calendar.gregorian(TimeZone(identifier: "UTC")!)
        let a = calendar.date(from: DateComponents(year: from.year, month: from.month, day: from.day))!
        let b = calendar.date(from: DateComponents(year: to.year, month: to.month, day: to.day))!
        return calendar.dateComponents([.day], from: a, to: b).day!
    }
}
