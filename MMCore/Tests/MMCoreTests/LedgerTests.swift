import Foundation
import Testing
@testable import MMCore

@Suite("帳本、成員、邀請、匯率")
struct LedgerTests {
    let membershipId = UUID()

    private func membershipJSON(role: String = "MEMBER", active: Bool = true) -> String {
        """
        {"id": "\(membershipId.apiString)", "user": {"id": 8, "username": "bob", "email": "b@x.com"},
         "role": "\(role)", "is_active": \(active), "joined_at": "2026-10-01T02:00:00.123456Z"}
        """
    }

    @Test("讀得懂成員、邀請和匯率")
    func decodes() async throws {
        let invitationJSON = """
        {"id": "\(UUID().apiString)", "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭"},
         "inviter": {"id": 7, "username": "alice", "email": ""}, "invitee": {"id": 8, "username": "bob", "email": ""},
         "status": "PENDING", "created_at": "2026-10-02T00:00:00Z"}
        """
        let (client, _, _) = makeClient { request in
            switch request.fullPath {
            case "/api/v2/ledgers/\(ledgerId.apiString)/members/": return json(200, "[\(membershipJSON(role: "ADMIN"))]")
            case "/api/v2/invitations/": return json(200, "[\(invitationJSON)]")
            default: return json(200, #"[{"currency": "JPY", "rate": "0.215000", "updated_by": null, "updated_at": "2026-10-02T00:00:00Z"}]"#)
            }
        }

        let members = try await client.members(ledger: ledgerId)
        let sent = try await client.sentInvitations(ledger: ledgerId)
        let rates = try await client.exchangeRates(ledger: ledgerId)

        #expect(members[0].role == .admin)
        #expect(members[0].user.username == "bob")
        #expect(sent.count == 1)
        #expect(sent[0].invitee.username == "bob")
        #expect(rates[0].currency == "JPY")
        #expect(rates[0].rate == Money(string: "0.215"))
    }

    @Test("改成員：只送有要改的欄位")
    func updateMember() async throws {
        let (client, transport, _) = makeClient { _ in json(200, membershipJSON(role: "ADMIN")) }

        _ = try await client.updateMember(ledger: ledgerId, membership: membershipId, role: .admin)

        let request = transport.requests[0]
        #expect(request.method == "PATCH")
        #expect(request.bodyJSON["role"] as? String == "ADMIN")
        #expect(request.bodyJSON["is_active"] == nil)
    }

    @Test("邀請：送使用者名稱和帳本；接受和拒絕是 POST")
    func invitations() async throws {
        let id = UUID()
        let (client, transport, _) = makeClient { _ in
            json(200, """
            {"id": "\(id.apiString)", "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭"},
             "inviter": {"id": 7, "username": "alice", "email": ""}, "invitee": {"id": 8, "username": "bob", "email": ""},
             "status": "PENDING", "created_at": "2026-10-02T00:00:00Z"}
            """)
        }

        _ = try await client.invite("bob", to: ledgerId)
        try await client.acceptInvitation(id)
        try await client.declineInvitation(id)

        #expect(transport.requests[0].bodyJSON["invitee"] as? String == "bob")
        #expect(transport.requests[0].bodyJSON["ledger"] as? String == ledgerId.apiString)
        #expect(transport.paths("POST") == ["/api/v2/invitations/",
                                            "/api/v2/invitations/\(id.apiString)/accept/",
                                            "/api/v2/invitations/\(id.apiString)/decline/"])
    }

    @Test("匯率整批取代：PUT，body 是 rates 清單，匯率是字串")
    func setExchangeRates() async throws {
        let (client, transport, _) = makeClient { _ in json(200, "[]") }

        _ = try await client.setExchangeRates(ledger: ledgerId, [("JPY", Money(string: "0.215")!)])

        let request = transport.requests[0]
        #expect(request.method == "PUT")
        let rates = request.bodyJSON["rates"] as? [[String: Any]]
        #expect(rates?.count == 1)
        #expect(rates?[0]["currency"] as? String == "JPY")
        #expect(rates?[0]["rate"] as? String == "0.215")
    }

    @Test("新增帳本：POST，不帶幣別時不送這個欄位")
    func createLedger() async throws {
        let (client, transport, _) = makeClient { _ in
            json(201, #"{"id": "\#(ledgerId.apiString)", "name": "家庭", "kind": "FAMILY", "base_currency": "TWD", "timezone": "Asia/Taipei", "member_count": 1, "my_role": "OWNER"}"#)
        }

        let ledger = try await client.createLedger(LedgerWrite(name: "家庭", timezone: "Asia/Taipei"))

        #expect(ledger.myRole == "OWNER")
        #expect(transport.requests[0].bodyJSON["base_currency"] == nil)
        #expect(transport.requests[0].bodyJSON["timezone"] as? String == "Asia/Taipei")
    }
}
