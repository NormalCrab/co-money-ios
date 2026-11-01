import Foundation
@testable import MMCore

/// 假的後端：依路徑回應，並記下收到的請求。
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) throws -> HTTPResponse

    private let lock = NSLock()
    private var handler: Handler
    private var _requests: [HTTPRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func paths(_ method: String? = nil) -> [String] {
        requests.filter { method == nil || $0.method == method }.map(\.fullPath)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let handler = lock.withLock {
            _requests.append(request)
            return self.handler
        }
        // 讓其他工作有機會插進來，才測得到同時發生的情況。
        await Task.yield()
        return try handler(request)
    }
}

let baseURL = URL(string: "https://example.test/")!

func json(_ status: Int, _ text: String) -> HTTPResponse {
    HTTPResponse(status: status, body: Data(text.utf8))
}

/// 做一個 simplejwt 形狀的 token（只有 payload 有意義）。
func jwt(userId: Int, tag: String = "a") -> String {
    let payload = try! JSONSerialization.data(withJSONObject: ["user_id": userId, "jti": tag])
    let base64 = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJIUzI1NiJ9.\(base64).sig"
}

func makeClient(tokens: AuthTokens? = AuthTokens(access: "access-1", refresh: "refresh-1"),
                _ handler: @escaping FakeTransport.Handler) -> (APIClient, FakeTransport, InMemoryTokenStore) {
    let transport = FakeTransport(handler)
    let store = InMemoryTokenStore(tokens)
    let session = AuthSession(baseURL: baseURL, transport: transport, store: store)
    return (APIClient(baseURL: baseURL, transport: transport, session: session), transport, store)
}

let ledgerId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

func transactionJSON(id: UUID = UUID(), description: String = "牛肉麵", amount: String = "180.00") -> String {
    """
    {"id": "\(id.apiString)", "description": "\(description)", "amount": "\(amount)", "currency": "TWD",
     "transaction_type": "EXPENSE", "category": "FOOD",
     "payer": {"id": 7, "username": "alice", "email": ""},
     "transaction_date": "2026-10-25T19:00:00+08:00", "notes": null,
     "ledger": {"id": "\(ledgerId.apiString)", "name": "家庭", "kind": "FAMILY", "base_currency": "TWD", "timezone": "Asia/Taipei"},
     "original_amount": null, "original_currency": null, "exchange_rate": null,
     "tags": [], "recurring_rule": null, "repeat": null,
     "created_at": "2026-10-26T05:00:00.123456Z", "updated_at": "2026-10-26T05:00:00.123456Z"}
    """
}

func parseJobJSON(id: UUID, status: String = "QUEUED", drafts: String = "[]") -> String {
    """
    {"id": "\(id.apiString)", "ledger_id": "\(ledgerId.apiString)", "source": "voice",
     "text": "晚餐牛肉麵 180", "captured_at": "2026-10-26T13:05:00Z", "status": "\(status)",
     "drafts": \(drafts), "error": "", "transaction_ids": [],
     "created_at": "2026-10-26T13:05:01.5Z", "updated_at": "2026-10-26T13:05:01.5Z"}
    """
}

let draftJSON = """
[{"description": "牛肉麵", "transaction_type": "EXPENSE", "transaction_date": "2026-10-25T12:00:00Z",
  "category": "FOOD", "notes": "", "original_amount": null, "original_currency": null,
  "exchange_rate": null, "amount": "180.00", "ledger_id": "\(ledgerId.apiString)"}]
"""

extension HTTPRequest {
    var bodyText: String { body.map { String(decoding: $0, as: UTF8.self) } ?? "" }
    var bodyJSON: [String: Any] {
        (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }
}

extension HTTPRequest {
    /// `URL.path` 會去掉結尾的斜線，Django 的網址都有斜線，所以用 URLComponents 讀。
    var fullPath: String { URLComponents(url: url, resolvingAgainstBaseURL: false)!.path }
}
