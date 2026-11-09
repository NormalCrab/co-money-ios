import Foundation

/// 提醒記帳的設定。存在這台手機上（不是帳號設定），預設關閉，使用者在「我」頁面打開才詢問通知權限。
public struct ReminderSettings: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var hour = 21
    public var minute = 0
    /// 要提醒的星期，ISO：1 是週一、7 是週日（和固定收支的每週規則一樣）。
    public var weekdays: Set<Int> = Set(1...7)

    public init() {}
}

/// 決定哪幾天要提醒。手機一次排好接下來的幾天（本機通知，不需要後端）；記了一筆就重排、跳過今天。
public enum ReminderPlanner {
    /// 接下來要提醒的日子：從今天起，星期有勾的前 `count` 天。
    /// 今天已經記過帳、或今天的提醒時間已經到了，就從明天開始。
    ///
    /// - Parameters:
    ///   - timeZone: 手機的時區（提醒跟著人走，不是帳本的時區）。
    ///   - lastRecorded: 最後一次記帳是哪一天（同一個時區）。
    public static func days(settings: ReminderSettings, now: Date, timeZone: TimeZone,
                            lastRecorded: LocalDate?, count: Int = 28) -> [LocalDate] {
        guard settings.isEnabled, !settings.weekdays.isEmpty, count > 0 else { return [] }
        let today = LocalDate(now, in: timeZone)
        let time = Calendar.gregorian(timeZone).dateComponents([.hour, .minute], from: now)
        let passed = (time.hour!, time.minute!) >= (settings.hour, settings.minute)

        var day = (passed || lastRecorded == today) ? today.nextDay : today
        var result: [LocalDate] = []
        // 最多看 count 週，避免只勾很少天時跑太久。
        for _ in 0..<(count * 7) where result.count < count {
            if settings.weekdays.contains(day.isoWeekday) { result.append(day) }
            day = day.nextDay
        }
        return result
    }
}

extension LocalDate {
    /// ISO 星期：1 是週一、7 是週日。
    public var isoWeekday: Int {
        let calendar = Calendar.gregorian(TimeZone(identifier: "UTC")!)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let weekday = calendar.component(.weekday, from: date)  // 1 是週日
        return (weekday + 5) % 7 + 1
    }
}
