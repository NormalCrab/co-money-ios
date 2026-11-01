import Foundation
import Testing
@testable import MMCore

@Suite("API client")
struct APIClientTests {
    @Test("讀得懂後端的交易：金額是字串、時間帶微秒和時區")
    func decodesTransaction() async throws {
        let (client, _, _) = makeClient { _ in
            json(200, #"{"count": 1, "next": null, "previous": null, "results": [\#(transactionJSON())]}"#)
        }

        let list = try await client.transactions(ledger: ledgerId, month: YearMonth(year: 2026, month: 10))

        #expect(list.count == 1)
        #expect(list[0].amount == Money(string: "180"))
        #expect(list[0].transactionDate == Date(timeIntervalSince1970: 1_792_926_000))
        #expect(list[0].payer.username == "alice")
    }

    @Test("交易列表帶帳本與月份，UUID 用小寫")
    func transactionQuery() async throws {
        let (client, transport, _) = makeClient { _ in
            json(200, #"{"count": 0, "next": null, "previous": null, "results": []}"#)
        }

        _ = try await client.transactions(ledger: ledgerId, month: YearMonth(year: 2026, month: 3))

        let url = transport.requests[0].url.absoluteString
        #expect(url.hasPrefix("https://example.test/api/v2/transactions/?"))
        #expect(url.contains("ledger=\(ledgerId.apiString)"))
        #expect(url.contains("month=3"))
        #expect(url.contains("year=2026"))
    }

    @Test("分頁會一直讀到最後一頁")
    func readsAllPages() async throws {
        let (client, transport, _) = makeClient { request in
            if request.url.query!.contains("page=1") {
                return json(200, #"{"count": 2, "next": "https://example.test/x?page=2", "previous": null, "results": [\#(transactionJSON())]}"#)
            }
            return json(200, #"{"count": 2, "next": null, "previous": null, "results": [\#(transactionJSON())]}"#)
        }

        let list = try await client.transactions(ledger: ledgerId, month: YearMonth(year: 2026, month: 10))

        #expect(list.count == 2)
        #expect(transport.requests.count == 2)
    }

    @Test("建立交易：送出手機產生的 id；201 是新的，200 是重送認出來的")
    func createTransaction() async throws {
        let id = UUID()
        let (client, transport, _) = makeClient { _ in json(200, transactionJSON(id: id)) }
        let input = TransactionInput(id: id, ledgerId: ledgerId, description: "牛肉麵", category: .food,
                                     transactionDate: Date(timeIntervalSince1970: 0), amount: 180)

        let result = try await client.createTransaction(input)

        guard case .existing = result else {
            Issue.record("200 應該當作既有的交易")
            return
        }
        let body = transport.requests[0].bodyJSON
        // JSONEncoder 把 UUID 寫成大寫，Django 的 UUIDField 不分大小寫，所以比較值。
        #expect((body["id"] as? String).flatMap(UUID.init(uuidString:)) == id)
        #expect((body["ledger_id"] as? String).flatMap(UUID.init(uuidString:)) == ledgerId)
        #expect(body["amount"] as? String == "180")
        #expect(body["transaction_date"] as? String == "1970-01-01T00:00:00.000Z")
        #expect(body["tag_ids"] as? [String] == [])
        #expect(transport.requests[0].headers["Authorization"] == "Bearer access-1")
    }

    @Test("修改交易：PATCH 到交易的網址，body 不帶 id，清掉備註時送空字串")
    func updateTransaction() async throws {
        let id = UUID()
        let (client, transport, _) = makeClient { _ in json(200, transactionJSON(id: id)) }
        let input = TransactionInput(id: id, ledgerId: ledgerId, description: "牛肉麵", category: .food,
                                     transactionDate: Date(timeIntervalSince1970: 0), amount: 200, notes: nil)

        let updated = try await client.updateTransaction(id, with: input)

        #expect(updated.id == id)
        let request = transport.requests[0]
        #expect(request.method == "PATCH")
        #expect(request.fullPath == "/api/v2/transactions/\(id.apiString)/")
        #expect(request.bodyJSON["id"] == nil)
        #expect(request.bodyJSON["notes"] as? String == "")
        #expect(request.bodyJSON["amount"] as? String == "200")
    }

    @Test("4xx 的錯誤訊息攤平成一句話，欄位也保留")
    func clientErrors() async throws {
        let (client, _, _) = makeClient { _ in
            json(400, #"{"tag_ids": ["伙食費 2026-09 不涵蓋 10/25"], "non_field_errors": ["帳本還沒設定 JPY 匯率"]}"#)
        }
        let input = TransactionInput(ledgerId: ledgerId, description: "拉麵", category: .food,
                                     transactionDate: Date(), originalAmount: 1200, originalCurrency: "JPY")

        await #expect(throws: APIError.client(
            status: 400, message: "帳本還沒設定 JPY 匯率；伙食費 2026-09 不涵蓋 10/25",
            fieldErrors: ["tag_ids": ["伙食費 2026-09 不涵蓋 10/25"], "non_field_errors": ["帳本還沒設定 JPY 匯率"]])
        ) {
            _ = try await client.createTransaction(input)
        }
    }

    @Test("網路錯誤歸類成 offline，5xx 歸類成 server")
    func networkAndServerErrors() async throws {
        struct Down: Error {}
        let (offline, _, _) = makeClient { _ in throw Down() }
        await #expect(throws: APIError.self) { _ = try await offline.ledgers() }
        do {
            _ = try await offline.ledgers()
        } catch let error as APIError {
            #expect(error.isRetryable)
            if case .offline = error {} else { Issue.record("應該是 offline：\(error)") }
        }

        let (broken, _, _) = makeClient { _ in json(502, "<html>Bad Gateway</html>") }
        await #expect(throws: APIError.server(status: 502)) { _ = try await broken.ledgers() }
    }

    @Test("解析工作：multipart 帶 id、記錄時間和檔案")
    func createParseJob() async throws {
        let id = UUID()
        let (client, transport, _) = makeClient { _ in json(202, parseJobJSON(id: id)) }
        let upload = ParseJobUpload(id: id, ledgerId: ledgerId, source: .voice, text: "晚餐牛肉麵 180",
                                    capturedAt: Date(timeIntervalSince1970: 1_793_019_900))

        let result = try await client.createParseJob(upload, audio: Data("m4a".utf8), image: nil)

        guard case .created(let job) = result else {
            Issue.record("202 應該是新建立的")
            return
        }
        #expect(job.status == .queued)
        let request = transport.requests[0]
        #expect(request.headers["Content-Type"]!.hasPrefix("multipart/form-data; boundary="))
        #expect(request.bodyText.contains("name=\"id\"\r\n\r\n\(id.apiString)\r\n"))
        #expect(request.bodyText.contains("name=\"captured_at\"\r\n\r\n2026-10-26T13:05:00.000Z\r\n"))
        #expect(request.bodyText.contains("filename=\"voice.m4a\""))
        #expect(!request.bodyText.contains("name=\"image\""))
    }

    @Test("解析結果可以變成要送出的交易")
    func draftToInput() async throws {
        let id = UUID()
        let (client, _, _) = makeClient { _ in json(200, parseJobJSON(id: id, status: "DONE", drafts: draftJSON)) }

        let job = try await client.parseJob(id)
        let input = job.drafts[0].input()

        #expect(job.status == .done)
        #expect(input.amount == 180)
        #expect(input.notes == nil)
        #expect(input.ledgerId == ledgerId)
    }

    @Test("列出解析工作時狀態用逗號分隔")
    func listParseJobs() async throws {
        let (client, transport, _) = makeClient { _ in json(200, "[]") }

        _ = try await client.parseJobs(status: [.done, .failed])

        #expect(transport.requests[0].url.query == "status=DONE,FAILED")
    }

    @Test("刪除已經不存在的交易當作成功")
    func deleteIsIdempotent() async throws {
        let (client, _, _) = makeClient { _ in json(404, #"{"detail": "Not found."}"#) }
        try await client.deleteTransaction(UUID())
    }
}

@Suite("錯誤訊息")
struct ErrorBodyTests {
    @Test("detail 直接用")
    func detail() {
        #expect(ErrorBody.parse(Data(#"{"detail": "你不是這個帳本的成員"}"#.utf8)).message == "你不是這個帳本的成員")
    }

    @Test("巢狀的清單（confirm 的每一筆）也攤平")
    func nested() {
        let body = Data(#"{"transactions": [{}, {"amount": ["請填金額"]}]}"#.utf8)
        #expect(ErrorBody.parse(body).message == "請填金額")
    }

    @Test("不是 JSON 時沒有訊息")
    func notJSON() {
        #expect(ErrorBody.parse(Data("<html>".utf8)).message == nil)
    }
}
