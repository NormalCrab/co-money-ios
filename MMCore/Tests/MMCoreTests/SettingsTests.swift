import Foundation
import Testing
@testable import MMCore

@Suite("設定：tag、週期預算規則、重複交易")
struct SettingsTests {
    let ruleId = UUID()

    private func recurringRuleJSON(description: String = "房租", next: String = "2026-11-05",
                                   endDate: String = "null", isActive: Bool = true) -> String {
        """
        {"id": "\(UUID().apiString)",
         "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭", "kind": "FAMILY", "base_currency": "TWD", "timezone": "Asia/Taipei"},
         "payer": {"id": 7, "username": "alice", "email": ""}, "description": "\(description)", "transaction_type": "EXPENSE",
         "category": "HOUSING", "notes": null, "amount": "20000.00", "original_amount": null, "original_currency": null,
         "tags": ["\(UUID().apiString)"], "frequency": "MONTHLY", "day": 5, "month": null, "start_date": "2026-10-05",
         "end_date": \(endDate), "next_run_date": "\(next)", "is_active": \(isActive), "created_by": null,
         "created_at": "2026-10-01T00:00:00Z"}
        """
    }

    @Test("首頁的固定收支：只列之後還會產生交易的，依下次執行日排序")
    func upcomingRecurring() throws {
        let decoder = APICoding.decoder()
        func rule(_ json: String) throws -> RecurringRule { try decoder.decode(RecurringRule.self, from: Data(json.utf8)) }
        let rules = try [
            rule(recurringRuleJSON(description: "保母費", next: "2026-11-15")),
            rule(recurringRuleJSON(description: "房租", next: "2026-11-05")),
            rule(recurringRuleJSON(description: "停用的", next: "2026-11-01", isActive: false)),
            // 下次執行日已經超過結束日：不會再產生了。
            rule(recurringRuleJSON(description: "到期的", next: "2026-12-05", endDate: #""2026-11-30""#)),
            rule(recurringRuleJSON(description: "最後一期", next: "2026-11-30", endDate: #""2026-11-30""#)),
        ]

        #expect(rules.upcoming().map(\.description) == ["房租", "保母費", "最後一期"])
    }

    @Test("從一筆交易設定固定收支：從交易的隔天開始（這筆不會再被產生一次），但不早於今天（不補產生過去的）")
    func firstStartFromTransaction() {
        let today = LocalDate(year: 2026, month: 11, day: 9)
        #expect(RecurringRule.firstStart(afterTransactionOn: LocalDate(year: 2026, month: 11, day: 5), today: today)
                == today)
        #expect(RecurringRule.firstStart(afterTransactionOn: today, today: today)
                == LocalDate(year: 2026, month: 11, day: 10))
        #expect(RecurringRule.firstStart(afterTransactionOn: LocalDate(year: 2026, month: 12, day: 31), today: today)
                == LocalDate(year: 2027, month: 1, day: 1))
    }

    /// 週期預算規則（§12.3）：沒有 is_active，改用 start_date / end_date。
    private func tagRuleJSON(endDate: String = "null") -> String {
        """
        {"id": "\(ruleId.apiString)", "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭"},
         "name": "伙食費", "budget_amount": "12000.00", "frequency": "MONTHLY", "start_day": 1, "start_month": null,
         "start_date": "2026-10-01", "end_date": \(endDate), "created_by": null, "created_at": "2026-10-01T00:00:00Z"}
        """
    }

    @Test("讀得懂重複交易規則和週期預算規則（§12 的期限格式）")
    func decodesRules() async throws {
        let (client, _, _) = makeClient { request in
            if request.fullPath == "/api/v2/tag-rules/" {
                return json(200, #"{"count": 1, "next": null, "previous": null, "results": [\#(tagRuleJSON())]}"#)
            }
            return json(200, #"{"count": 1, "next": null, "previous": null, "results": [\#(recurringRuleJSON())]}"#)
        }

        let tagRules = try await client.tagRules(ledger: ledgerId)
        let recurring = try await client.recurringRules(ledger: ledgerId)

        #expect(tagRules[0].frequency == .monthly)
        #expect(tagRules[0].budgetAmount == Money(string: "12000"))
        #expect(tagRules[0].startDate == LocalDate(year: 2026, month: 10, day: 1))
        #expect(tagRules[0].endDate == nil)
        #expect(recurring[0].day == 5)
        #expect(recurring[0].startDate == LocalDate(year: 2026, month: 10, day: 5))
        #expect(recurring[0].endDate == nil)
        #expect(recurring[0].amount == Money(string: "20000"))
    }

    @Test("規則還在不在進行中：沒有結束日，或結束日是今天或之後")
    func ruleOngoing() throws {
        let decoder = APICoding.decoder()
        let open = try decoder.decode(TagRule.self, from: Data(tagRuleJSON().utf8))
        let ended = try decoder.decode(TagRule.self, from: Data(tagRuleJSON(endDate: #""2026-10-31""#).utf8))

        #expect(open.isOngoing(today: LocalDate(year: 2030, month: 1, day: 1)))
        #expect(ended.isOngoing(today: LocalDate(year: 2026, month: 10, day: 31)))
        #expect(!ended.isOngoing(today: LocalDate(year: 2026, month: 11, day: 1)))
    }

    @Test("新增規則沒給開始日就不送（後端用帳本的今天）；結束日一定送，null 表示一直持續")
    func tagRuleWrites() async throws {
        let (client, transport, _) = makeClient { _ in json(200, tagRuleJSON()) }

        _ = try await client.createTagRule(TagRuleWrite(ledgerId: ledgerId, name: "伙食費", budgetAmount: 12000,
                                                        frequency: .monthly))
        _ = try await client.updateTagRule(ruleId, with: TagRuleWrite(
            name: "伙食費", budgetAmount: 12000, frequency: .monthly,
            startDate: LocalDate(year: 2026, month: 9, day: 1), endDate: LocalDate(year: 2026, month: 12, day: 31)))

        let created = transport.requests[0]
        #expect(created.method == "POST")
        #expect(created.bodyJSON["ledger_id"] != nil)
        #expect(created.bodyJSON["start_date"] == nil)
        #expect(created.bodyJSON["end_date"] is NSNull)
        #expect(created.bodyJSON["is_active"] == nil)

        let updated = transport.requests[1]
        #expect(updated.method == "PATCH")
        #expect(updated.fullPath == "/api/v2/tag-rules/\(ruleId.apiString)/")
        #expect(updated.bodyJSON["ledger_id"] == nil)
        #expect(updated.bodyJSON["start_date"] as? String == "2026-09-01")
        #expect(updated.bodyJSON["end_date"] as? String == "2026-12-31")
    }

    @Test("新增 tag 帶帳本；修改不帶帳本，清掉預算要送 null；一次性 tag 的期限可以寫、可以清掉")
    func tagWrites() async throws {
        let tagJSON = """
        {"id": "\(UUID().apiString)", "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭"}, "name": "旅遊",
         "budget_amount": null, "period_start": null, "period_end": "2026-11-27", "rule": null, "rule_name": null,
         "is_periodic": false, "is_ended": false, "spent": "0", "remaining": null}
        """
        let (client, transport, _) = makeClient { _ in json(200, tagJSON) }

        let created = try await client.createTag(TagWrite(
            ledgerId: ledgerId, name: "旅遊", budgetAmount: 5000,
            period: .init(start: nil, end: LocalDate(year: 2026, month: 11, day: 27))))
        _ = try await client.updateTag(UUID(), with: TagWrite(name: "旅遊", budgetAmount: nil))

        #expect(created.periodEnd == LocalDate(year: 2026, month: 11, day: 27))
        #expect(created.isEnded == false)

        let createRequest = transport.requests[0]
        #expect(createRequest.method == "POST")
        #expect(createRequest.fullPath == "/api/v2/tags/")
        #expect(createRequest.bodyJSON["budget_amount"] as? String == "5000")
        #expect(createRequest.bodyJSON["ledger_id"] != nil)
        #expect(createRequest.bodyJSON["period_start"] is NSNull)
        #expect(createRequest.bodyJSON["period_end"] as? String == "2026-11-27")

        // 週期 tag 的某一期：不給 period 就完全不送期限（後端會拒絕改週期 tag 的期限）。
        let updateRequest = transport.requests[1]
        #expect(updateRequest.method == "PATCH")
        #expect(updateRequest.bodyJSON["ledger_id"] == nil)
        #expect(updateRequest.bodyJSON["budget_amount"] is NSNull)
        #expect(updateRequest.bodyJSON["period_start"] == nil)
        #expect(updateRequest.bodyJSON["period_end"] == nil)
        #expect(updateRequest.bodyJSON["is_archived"] == nil)
    }

    @Test("讀某個月的 tag：用 year + month 篩選期限重疊的（§12.6），不再送 is_archived")
    func monthTags() async throws {
        let (client, transport, _) = makeClient { _ in json(200, #"{"count": 0, "next": null, "previous": null, "results": []}"#) }

        _ = try await client.tags(ledger: ledgerId, month: YearMonth(year: 2026, month: 9))

        let query = transport.requests[0].query
        #expect(query["ledger"] == ledgerId.apiString)
        #expect(query["year"] == "2026")
        #expect(query["month"] == "9")
        #expect(query["is_archived"] == nil)
    }

    @Test("重複交易規則：外幣改本幣時，沒用到的金額欄位要明確送 null；tag 的欄位叫 tags")
    func recurringWrite() async throws {
        let (client, transport, _) = makeClient { _ in json(200, recurringRuleJSON()) }
        let tagId = UUID()
        let rule = RecurringRuleWrite(
            description: "房租", transactionType: .expense, category: .housing, amount: 20000, tags: [tagId],
            frequency: .monthly, day: 5, startDate: LocalDate(year: 2026, month: 10, day: 5))

        let ruleId = UUID()
        _ = try await client.updateRecurringRule(ruleId, with: rule)

        let request = transport.requests[0]
        #expect(request.method == "PATCH")
        #expect(request.fullPath == "/api/v2/recurring-rules/\(ruleId.apiString)/")
        #expect(request.bodyJSON["amount"] as? String == "20000")
        #expect(request.bodyJSON["original_amount"] is NSNull)
        #expect(request.bodyJSON["original_currency"] is NSNull)
        #expect(request.bodyJSON["end_date"] is NSNull)
        #expect(request.bodyJSON["start_date"] as? String == "2026-10-05")
        #expect((request.bodyJSON["tags"] as? [String])?.count == 1)
        #expect(request.bodyJSON["frequency"] as? String == "MONTHLY")
    }
}
