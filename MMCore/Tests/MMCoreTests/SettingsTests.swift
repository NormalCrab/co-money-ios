import Foundation
import Testing
@testable import MMCore

@Suite("設定：tag、週期預算規則、重複交易")
struct SettingsTests {
    let ruleId = UUID()

    private func recurringRuleJSON() -> String {
        """
        {"id": "\(ruleId.apiString)",
         "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭", "kind": "FAMILY", "base_currency": "TWD", "timezone": "Asia/Taipei"},
         "payer": {"id": 7, "username": "alice", "email": ""}, "description": "房租", "transaction_type": "EXPENSE",
         "category": "HOUSING", "notes": null, "amount": "20000.00", "original_amount": null, "original_currency": null,
         "tags": ["\(UUID().apiString)"], "frequency": "MONTHLY", "day": 5, "start_date": "2026-10-05", "end_date": null,
         "next_run_date": "2026-11-05", "is_active": true, "created_by": null, "created_at": "2026-10-01T00:00:00Z"}
        """
    }

    @Test("讀得懂重複交易規則和週期預算規則")
    func decodesRules() async throws {
        let (client, _, _) = makeClient { request in
            if request.fullPath == "/api/v2/tag-rules/" {
                return json(200, """
                {"count": 1, "next": null, "previous": null, "results": [
                 {"id": "\(UUID().apiString)", "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭"},
                  "name": "伙食費", "budget_amount": "12000.00", "frequency": "MONTHLY", "is_active": true,
                  "created_by": null, "created_at": "2026-10-01T00:00:00Z"}]}
                """)
            }
            return json(200, #"{"count": 1, "next": null, "previous": null, "results": [\#(recurringRuleJSON())]}"#)
        }

        let tagRules = try await client.tagRules(ledger: ledgerId)
        let recurring = try await client.recurringRules(ledger: ledgerId)

        #expect(tagRules[0].frequency == .monthly)
        #expect(tagRules[0].budgetAmount == Money(string: "12000"))
        #expect(recurring[0].day == 5)
        #expect(recurring[0].startDate == LocalDate(year: 2026, month: 10, day: 5))
        #expect(recurring[0].endDate == nil)
        #expect(recurring[0].amount == Money(string: "20000"))
    }

    @Test("新增 tag 帶帳本；修改不帶帳本，清掉預算要送 null")
    func tagWrites() async throws {
        let tagJSON = """
        {"id": "\(UUID().apiString)", "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭"}, "name": "旅遊",
         "budget_amount": null, "is_archived": false, "period_start": null, "period_end": null, "rule": null,
         "is_periodic": false, "spent": "0", "remaining": null}
        """
        let (client, transport, _) = makeClient { _ in json(200, tagJSON) }

        _ = try await client.createTag(TagWrite(ledgerId: ledgerId, name: "旅遊", budgetAmount: 5000))
        _ = try await client.updateTag(UUID(), with: TagWrite(name: "旅遊", budgetAmount: nil, isArchived: true))

        let created = transport.requests[0]
        #expect(created.method == "POST")
        #expect(created.fullPath == "/api/v2/tags/")
        #expect(created.bodyJSON["budget_amount"] as? String == "5000")
        #expect(created.bodyJSON["ledger_id"] != nil)

        let updated = transport.requests[1]
        #expect(updated.method == "PATCH")
        #expect(updated.bodyJSON["ledger_id"] == nil)
        #expect(updated.bodyJSON["budget_amount"] is NSNull)
        #expect(updated.bodyJSON["is_archived"] as? Bool == true)
    }

    @Test("重複交易規則：外幣改本幣時，沒用到的金額欄位要明確送 null；tag 的欄位叫 tags")
    func recurringWrite() async throws {
        let (client, transport, _) = makeClient { _ in json(200, recurringRuleJSON()) }
        let tagId = UUID()
        let rule = RecurringRuleWrite(
            description: "房租", transactionType: .expense, category: .housing, amount: 20000, tags: [tagId],
            frequency: .monthly, day: 5, startDate: LocalDate(year: 2026, month: 10, day: 5))

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
