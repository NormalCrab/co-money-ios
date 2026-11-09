import Foundation
import Testing
@testable import MMCore

@Suite("提醒記帳")
struct ReminderTests {
    let taipei = TimeZone(identifier: "Asia/Taipei")!

    /// 台北時間的某個時刻。
    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.gregorian(taipei).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var enabled: ReminderSettings {
        var settings = ReminderSettings()
        settings.isEnabled = true
        return settings
    }

    @Test("預設：關閉、每晚 21:00、每天")
    func defaults() {
        let settings = ReminderSettings()
        #expect(!settings.isEnabled)
        #expect(settings.hour == 21 && settings.minute == 0)
        #expect(settings.weekdays == Set(1...7))
    }

    @Test("關閉時不排任何提醒")
    func disabled() {
        #expect(ReminderPlanner.days(settings: ReminderSettings(), now: at(2026, 11, 9, 10), timeZone: taipei,
                                     lastRecorded: nil).isEmpty)
    }

    @Test("今天還沒到提醒時間、也還沒記帳：從今天開始，排 count 天")
    func startsToday() {
        let days = ReminderPlanner.days(settings: enabled, now: at(2026, 11, 9, 10), timeZone: taipei,
                                        lastRecorded: nil, count: 3)
        #expect(days == [LocalDate(year: 2026, month: 11, day: 9), LocalDate(year: 2026, month: 11, day: 10),
                         LocalDate(year: 2026, month: 11, day: 11)])
    }

    @Test("今天已經記過帳：跳過今天")
    func skipsRecordedToday() {
        let days = ReminderPlanner.days(settings: enabled, now: at(2026, 11, 9, 10), timeZone: taipei,
                                        lastRecorded: LocalDate(year: 2026, month: 11, day: 9), count: 2)
        #expect(days == [LocalDate(year: 2026, month: 11, day: 10), LocalDate(year: 2026, month: 11, day: 11)])
    }

    @Test("昨天記過不影響今天")
    func yesterdayDoesNotCount() {
        let days = ReminderPlanner.days(settings: enabled, now: at(2026, 11, 9, 10), timeZone: taipei,
                                        lastRecorded: LocalDate(year: 2026, month: 11, day: 8), count: 1)
        #expect(days == [LocalDate(year: 2026, month: 11, day: 9)])
    }

    @Test("今天的提醒時間已經過了：從明天開始（21:00 整也算過了）")
    func timePassed() {
        let late = ReminderPlanner.days(settings: enabled, now: at(2026, 11, 9, 21, 30), timeZone: taipei,
                                        lastRecorded: nil, count: 1)
        let exact = ReminderPlanner.days(settings: enabled, now: at(2026, 11, 9, 21, 0), timeZone: taipei,
                                         lastRecorded: nil, count: 1)
        #expect(late == [LocalDate(year: 2026, month: 11, day: 10)])
        #expect(exact == [LocalDate(year: 2026, month: 11, day: 10)])
    }

    @Test("只排有勾的星期（ISO：1 是週一、7 是週日）；跨月也照算")
    func weekdays() {
        var settings = enabled
        settings.weekdays = [1, 5]  // 週一、週五
        // 2026-11-09 是週一。
        let days = ReminderPlanner.days(settings: settings, now: at(2026, 11, 9, 10), timeZone: taipei,
                                        lastRecorded: nil, count: 4)
        #expect(days == [LocalDate(year: 2026, month: 11, day: 9), LocalDate(year: 2026, month: 11, day: 13),
                         LocalDate(year: 2026, month: 11, day: 16), LocalDate(year: 2026, month: 11, day: 20)])
    }

    @Test("ISO 星期")
    func isoWeekday() {
        #expect(LocalDate(year: 2026, month: 11, day: 9).isoWeekday == 1)   // 週一
        #expect(LocalDate(year: 2026, month: 11, day: 15).isoWeekday == 7)  // 週日
    }

    @Test("設定存起來讀得回來")
    func codable() throws {
        var settings = enabled
        settings.hour = 22
        settings.minute = 30
        settings.weekdays = [1, 2, 3]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(ReminderSettings.self, from: data) == settings)
    }
}
