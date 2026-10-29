import Foundation
import Testing
@testable import MMCore

/// 對真的後端跑一遍（平常跳過）。用 staging 的測試帳號：
///
///     MM_LIVE_URL=https://newsroom.codai8.com/ MM_LIVE_USER=... MM_LIVE_PASSWORD=... \
///       swift test --filter Live
///
/// 會在第一個帳本建立交易和解析工作，跑完刪掉交易、捨棄沒用到的解析工作。
/// 解析會真的呼叫 LLM。
@Suite("Live（真的後端）", .enabled(if: ProcessInfo.processInfo.environment["MM_LIVE_URL"] != nil))
struct LiveTests {
    let env = ProcessInfo.processInfo.environment

    func client() async throws -> APIClient {
        let base = URL(string: env["MM_LIVE_URL"]!)!
        let transport = URLSessionTransport()
        let session = AuthSession(baseURL: base, transport: transport, store: InMemoryTokenStore())
        try await session.login(username: env["MM_LIVE_USER"]!, password: env["MM_LIVE_PASSWORD"]!)
        return APIClient(baseURL: base, transport: transport, session: session)
    }

    @Test("登入、讀帳本、建立交易（重送不會重複）、刪除")
    func transactions() async throws {
        let api = try await client()
        let ledger = try #require(try await api.ledgers().first)
        let month = YearMonth(Date(), in: ledger.timeZone)
        _ = try await api.categorySummary(ledger: ledger.id, month: month)
        _ = try await api.activeTags(ledger: ledger.id)

        let input = TransactionInput(ledgerId: ledger.id, description: "MMCore live test", category: .other,
                                     transactionDate: Date(), amount: Money(string: "12.5"))
        let first = try await api.createTransaction(input)
        let again = try await api.createTransaction(input)
        defer { Task { try? await api.deleteTransaction(input.id) } }

        guard case .created = first, case .existing = again else {
            Issue.record("第一次應該是 created、第二次 existing")
            return
        }
        #expect(again.value.id == input.id)
        #expect(again.value.amount == Money(string: "12.5"))
        let listed = try await api.transactions(ledger: ledger.id, month: month)
        #expect(listed.contains { $0.id == input.id })
        try await api.deleteTransaction(input.id)
        try await api.deleteTransaction(input.id)  // 第二次是 404，當作成功
    }

    @Test("解析工作：送出、等結果、確認、確認重送回傳同一批")
    func parseJob() async throws {
        let api = try await client()
        let ledger = try #require(try await api.ledgers().first)
        let upload = ParseJobUpload(ledgerId: ledger.id, source: .manual, text: "MMCore 測試 午餐便當 120",
                                    capturedAt: Date())

        let created = try await api.createParseJob(upload, audio: nil, image: tinyJPEG)
        let again = try await api.createParseJob(upload, audio: nil, image: nil)
        guard case .created = created, case .existing = again else {
            Issue.record("第一次應該是 created、第二次 existing")
            return
        }

        let job = try #require(try await ParseJobWaiter.wait(for: upload.id, timeout: .seconds(90),
                                                             fetch: { try await api.parseJob($0) }))
        guard job.status == .done, let draft = job.drafts.first else {
            Issue.record("解析失敗：\(job.status) \(job.error)")
            try? await api.discardParseJob(upload.id)
            return
        }
        #expect(draft.amount == 120)

        let input = draft.input()
        let confirmed = try await api.confirmParseJob(upload.id, transactions: [input])
        let repeated = try await api.confirmParseJob(upload.id, transactions: [input])
        #expect(confirmed.map(\.id) == [input.id])
        #expect(repeated.map(\.id) == [input.id])
        #expect(try await api.parseJob(upload.id).status == .confirmed)
        try await api.deleteTransaction(input.id)
    }
}

/// 1×1 的白色 JPEG（後端會檢查上傳的是不是真的圖片）。
private let tinyJPEG = Data(base64Encoded: "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q==")!
