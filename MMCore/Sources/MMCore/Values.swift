import Foundation

/// 金額。API 一律用字串傳（Django 的 Decimal），這裡解成 `Decimal`，送出時再轉回字串。
///
/// 不用 `Double`：0.1 + 0.2 這種誤差在記帳裡不能接受。
public struct Money: Codable, Hashable, Sendable, Comparable, ExpressibleByIntegerLiteral {
    public var value: Decimal

    public init(_ value: Decimal) { self.value = value }
    public init(integerLiteral value: Int) { self.value = Decimal(value) }

    /// 從使用者輸入或 API 字串建立。去掉千分位逗號；不是數字回傳 nil。
    public init?(string: String) {
        let cleaned = string.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            guard let money = Money(string: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "金額不是數字：\(text)")
            }
            self = money
        } else {
            self.value = try container.decode(Decimal.self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(apiString)
    }

    /// 送給 API 的字串，例如 "1280" 或 "12.5"。
    public var apiString: String {
        NSDecimalNumber(decimal: value).stringValue
    }

    /// 顯示用：千分位、最多兩位小數，例如 "1,280"、"12.5"。
    public var display: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? apiString
    }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.value < rhs.value }
    public static func + (lhs: Money, rhs: Money) -> Money { Money(lhs.value + rhs.value) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(lhs.value - rhs.value) }
    public static let zero = Money(0)
}

/// 沒有時間的日期（tag 的期間 `period_start` / `period_end`），API 格式 "2026-10-01"。
///
/// 和 `Date` 分開：`Date` 是一個瞬間，換時區就會變成別的日子；這裡的日期不屬於任何時區。
public struct LocalDate: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// 某個瞬間在指定時區是哪一天。
    public init(_ date: Date, in timeZone: TimeZone) {
        let parts = Calendar.gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(string: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "日期格式錯誤：\(text)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension Calendar {
    /// 公曆，指定時區。不用 `Calendar.current`：使用者手機設成日本曆或佛曆時年份會不對。
    public static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "zh_TW")
        return calendar
    }
}

/// API 的 JSON 設定：snake_case、ISO 8601 時間（Django 會帶微秒和時區）。
public enum APICoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "時間格式錯誤：\(text)")
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// 解析 "2026-10-25T19:00:00+08:00"、"2026-10-25T11:00:00.123456Z" 這類字串。
    public static func parseDate(_ text: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    /// 送給 API 的時間：UTC，到毫秒。
    public static func formatDate(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
