import Foundation
import Testing
@testable import MMCore

@Suite("金額")
struct MoneyTests {
    @Test("從字串讀，去掉千分位")
    func parse() {
        #expect(Money(string: "1,280") == 1280)
        #expect(Money(string: " 12.5 ")?.value == Decimal(string: "12.5"))
        #expect(Money(string: "") == nil)
        #expect(Money(string: "abc") == nil)
    }

    @Test("送給 API 的字串和顯示用的字串")
    func format() {
        #expect(Money(string: "1280.00")!.apiString == "1280")
        #expect(Money(string: "12345.5")!.display == "12,345.5")
        #expect(Money(-500).display == "-500")
    }

    @Test("沒有浮點誤差")
    func exact() {
        #expect(Money(string: "0.1")! + Money(string: "0.2")! == Money(string: "0.3")!)
    }

    @Test("用匯率預估換算後的金額，四捨五入到小數兩位")
    func convert() {
        // 1 JPY = 0.215 TWD：1000 日圓約 215 台幣。
        #expect(Money(1000).converted(at: Money(string: "0.215")!) == 215)
        // 1 JPY = 0.2153 TWD：999 日圓 = 215.0847 → 215.08。
        #expect(Money(999).converted(at: Money(string: "0.2153")!) == Money(string: "215.08")!)
        // 進位：0.005 → 0.01。
        #expect(Money(string: "0.5")!.converted(at: Money(string: "0.01")!) == Money(string: "0.01")!)
    }
}

@Suite("日期")
struct CalendarTests {
    let taipei = TimeZone(identifier: "Asia/Taipei")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    @Test("月份依帳本時區：台北 11/1 00:30 是 11 月，UTC 還是 10 月")
    func monthInTimeZone() {
        let moment = APICoding.parseDate("2026-10-31T16:30:00Z")!
        #expect(YearMonth(moment, in: taipei) == YearMonth(year: 2026, month: 11))
        #expect(YearMonth(moment, in: TimeZone(identifier: "UTC")!) == YearMonth(year: 2026, month: 10))
    }

    @Test("月份的起訖")
    func interval() {
        let range = YearMonth(year: 2026, month: 12).interval(in: taipei)
        #expect(range.lowerBound == APICoding.parseDate("2026-11-30T16:00:00Z"))
        #expect(range.upperBound == APICoding.parseDate("2026-12-31T16:00:00Z"))
    }

    @Test("前後一個月跨年")
    func neighbours() {
        #expect(YearMonth(year: 2026, month: 1).previous == YearMonth(year: 2025, month: 12))
        #expect(YearMonth(year: 2026, month: 12).next == YearMonth(year: 2027, month: 1))
    }

    @Test("交易列表的日期標題")
    func dayHeader() {
        let today = LocalDate(year: 2026, month: 10, day: 27)
        #expect(DateText.dayHeader(today, today: today) == "今天 10/27（二）")
        #expect(DateText.dayHeader(LocalDate(year: 2026, month: 10, day: 26), today: today) == "昨天 10/26（一）")
        #expect(DateText.dayHeader(LocalDate(year: 2026, month: 10, day: 25), today: today) == "10/25（日）")
        #expect(DateText.dayHeader(LocalDate(year: 2025, month: 12, day: 31), today: today) == "2025/12/31（三）")
    }

    @Test("隔天：跨月、跨年、閏年")
    func nextDay() {
        #expect(LocalDate(year: 2026, month: 11, day: 9).nextDay == LocalDate(year: 2026, month: 11, day: 10))
        #expect(LocalDate(year: 2026, month: 2, day: 28).nextDay == LocalDate(year: 2026, month: 3, day: 1))
        #expect(LocalDate(year: 2028, month: 2, day: 28).nextDay == LocalDate(year: 2028, month: 2, day: 29))
        #expect(LocalDate(year: 2026, month: 12, day: 31).nextDay == LocalDate(year: 2027, month: 1, day: 1))
    }

    @Test("期限的文字：跨年才寫年份；一次性 tag 可以只有一端")
    func period() {
        let oct1 = LocalDate(year: 2026, month: 10, day: 1)
        let oct31 = LocalDate(year: 2026, month: 10, day: 31)
        #expect(DateText.period(start: oct1, end: oct31) == "10/1 ~ 10/31")
        #expect(DateText.period(start: LocalDate(year: 2026, month: 12, day: 25),
                                end: LocalDate(year: 2027, month: 1, day: 3)) == "2026/12/25 ~ 2027/1/3")
        #expect(DateText.period(start: nil, end: oct31) == "~ 10/31")
        #expect(DateText.period(start: oct1, end: nil) == "10/1 ~")
        #expect(DateText.period(start: nil, end: nil) == nil)
    }

    @Test("時間依時區")
    func time() {
        let moment = APICoding.parseDate("2026-10-27T02:42:00Z")!
        #expect(DateText.time(moment, in: taipei) == "10:42")
        #expect(DateText.time(moment, in: tokyo) == "11:42")
    }

    @Test("Django 的各種時間格式都讀得懂")
    func parseDates() {
        let expected = Date(timeIntervalSince1970: 1_792_926_000)
        #expect(APICoding.parseDate("2026-10-25T19:00:00+08:00") == expected)
        #expect(APICoding.parseDate("2026-10-25T11:00:00Z") == expected)
        #expect(APICoding.parseDate("2026-10-25T11:00:00.000000Z") == expected)
        #expect(APICoding.parseDate("2026-10-25T11:00:00.123456Z")! > expected)
    }

    @Test("週期 tag 只涵蓋期間內的日子")
    func tagCovers() {
        let tag = Tag(id: UUID(), name: "伙食費 2026-10",
                      periodStart: LocalDate(year: 2026, month: 10, day: 1),
                      periodEnd: LocalDate(year: 2026, month: 10, day: 31), isPeriodic: true)
        #expect(tag.covers(LocalDate(year: 2026, month: 10, day: 31)))
        #expect(!tag.covers(LocalDate(year: 2026, month: 11, day: 1)))
        #expect(Tag(id: UUID(), name: "日本出遊").covers(LocalDate(year: 2030, month: 1, day: 1)))
    }
}

@Suite("快取")
struct CacheTests {
    @Test("存進去讀得回來，記得更新時間")
    func roundTrip() {
        let cache = JSONCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID())"))
        defer { cache.clear() }
        let ledger = Ledger(id: ledgerId, name: "家庭", kind: .family)
        let at = Date(timeIntervalSince1970: 1_793_019_900)

        cache.save([ledger], key: "ledgers", at: at)
        let entry = cache.load([Ledger].self, key: "ledgers")

        #expect(entry?.value == [ledger])
        #expect(entry?.updatedAt == at)
        cache.clear()
        #expect(cache.load([Ledger].self, key: "ledgers") == nil)
    }
}
