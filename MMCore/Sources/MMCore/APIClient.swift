import Foundation

/// 建立類請求的結果：新建立的，還是重送時後端認出是同一筆（ios-design §3.1）。
public enum Created<Value: Sendable>: Sendable {
    case created(Value)
    case existing(Value)

    public var value: Value {
        switch self {
        case .created(let value), .existing(let value): value
        }
    }
}

/// 後端 API。每個方法對應一個 endpoint，失敗一律丟 `APIError`。
///
/// 收到 401 時先換 token 再重送一次；換不到就丟 `.unauthorized`。
public struct APIClient: Sendable {
    public let baseURL: URL
    public let session: AuthSession
    private let transport: HTTPTransport

    public init(baseURL: URL, transport: HTTPTransport, session: AuthSession) {
        self.baseURL = baseURL
        self.transport = transport
        self.session = session
    }

    // MARK: 帳本與設定

    public func ledgers() async throws -> [Ledger] {
        try await get("api/v2/ledgers/")
    }

    /// 某個月各分類的淨額（月份界線依帳本時區，後端算）。
    public func categorySummary(ledger: UUID, month: YearMonth) async throws -> [CategorySummaryItem] {
        try await get("api/v2/ledgers/\(ledger.apiString)/category-summary/", query: [
            "year": "\(month.year)", "month": "\(month.month)",
        ])
    }

    /// 帳本裡還沒封存的 tag（預算）。
    public func activeTags(ledger: UUID) async throws -> [Tag] {
        try await getAllPages("api/v2/tags/", query: ["ledger": ledger.apiString, "is_archived": "false"])
    }

    // MARK: 交易

    public func transactions(ledger: UUID, month: YearMonth) async throws -> [Transaction] {
        try await getAllPages("api/v2/transactions/", query: [
            "ledger": ledger.apiString, "year": "\(month.year)", "month": "\(month.month)",
            "page_size": "200",
        ])
    }

    /// 建立交易。同一個 `id` 重送時後端回 200 和既有的那筆。
    public func createTransaction(_ input: TransactionInput) async throws -> Created<Transaction> {
        let response = try await send("POST", "api/v2/transactions/", json: input)
        let transaction: Transaction = try decode(response)
        return response.status == 201 ? .created(transaction) : .existing(transaction)
    }

    /// 修改已上傳的交易（需要連線，不進待上傳佇列）。只有付款人本人，或帳本的擁有者 / 管理員可以改。
    public func updateTransaction(_ id: UUID, with input: TransactionInput) async throws -> Transaction {
        try decode(try await send("PATCH", "api/v2/transactions/\(id.apiString)/", json: TransactionPatch(input)))
    }

    public func deleteTransaction(_ id: UUID) async throws {
        do {
            _ = try await send("DELETE", "api/v2/transactions/\(id.apiString)/")
        } catch APIError.client(status: 404, _, _) {
            // 已經刪掉了（例如上次的回應沒收到），當作成功。
        }
    }

    // MARK: 解析工作（ios-design §2.2）

    /// 建立解析工作。檔案已經讀進記憶體（音檔約 0.5 MB、圖片約 1 MB）。
    public func createParseJob(_ upload: ParseJobUpload, audio: Data?, image: Data?) async throws -> Created<ParseJob> {
        var form = MultipartForm()
        form.add("id", upload.id.apiString)
        form.add("ledger_id", upload.ledgerId.apiString)
        form.add("source", upload.source.rawValue)
        form.add("text", upload.text)
        form.add("captured_at", APICoding.formatDate(upload.capturedAt))
        if let audio {
            form.addFile("audio", filename: "voice.m4a", mimeType: "audio/mp4", data: audio)
        }
        if let image {
            form.addFile("image", filename: "receipt.jpg", mimeType: "image/jpeg", data: image)
        }
        let response = try await send("POST", "api/v2/parse-jobs/", body: form.body, contentType: form.contentType)
        let job: ParseJob = try decode(response)
        return response.status == 202 ? .created(job) : .existing(job)
    }

    /// 列出自己的解析工作。不給狀態時是還沒結束的（排隊、解析中、待確認、失敗）。
    public func parseJobs(status: [ParseJobStatus] = []) async throws -> [ParseJob] {
        let query = status.isEmpty ? [:] : ["status": status.map(\.rawValue).joined(separator: ",")]
        return try await get("api/v2/parse-jobs/", query: query)
    }

    public func parseJob(_ id: UUID) async throws -> ParseJob {
        try await get("api/v2/parse-jobs/\(id.apiString)/")
    }

    /// 確認解析結果，一次建立這些交易。重送回傳同一批。
    public func confirmParseJob(_ id: UUID, transactions: [TransactionInput]) async throws -> [Transaction] {
        struct Body: Encodable { var transactions: [TransactionInput] }
        let response = try await send("POST", "api/v2/parse-jobs/\(id.apiString)/confirm/",
                                      json: Body(transactions: transactions))
        return try decode(response)
    }

    public func discardParseJob(_ id: UUID) async throws {
        _ = try await send("POST", "api/v2/parse-jobs/\(id.apiString)/discard/")
    }

    public func retryParseJob(_ id: UUID) async throws -> ParseJob {
        try decode(try await send("POST", "api/v2/parse-jobs/\(id.apiString)/retry/"))
    }

    // MARK: 底層

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try decode(try await send("GET", path, query: query))
    }

    /// 讀完所有分頁。`next` 是完整網址，只取它的 query 接著讀。
    func getAllPages<T: Codable & Sendable>(_ path: String, query: [String: String]) async throws -> [T] {
        var results: [T] = []
        var page = 1
        while true {
            var pageQuery = query
            pageQuery["page"] = "\(page)"
            let response: Paginated<T> = try await get(path, query: pageQuery)
            results += response.results
            guard response.next != nil, !response.results.isEmpty, page < 50 else { return results }
            page += 1
        }
    }

    func send<Body: Encodable>(_ method: String, _ path: String, json: Body) async throws -> HTTPResponse {
        let data: Data
        do {
            data = try APICoding.encoder().encode(json)
        } catch {
            throw APIError.decoding("無法編碼：\(error)")
        }
        return try await send(method, path, body: data, contentType: "application/json")
    }

    /// 送出請求並處理登入：帶上 access token；401 時換 token 重送一次。
    /// 2xx 回傳回應，其他狀態碼丟 `APIError`。
    func send(_ method: String, _ path: String, query: [String: String] = [:],
              body: Data? = nil, contentType: String? = nil) async throws -> HTTPResponse {
        var request = HTTPRequest(method: method, url: url(path, query: query), body: body)
        request.headers["Accept"] = "application/json"
        if let contentType { request.headers["Content-Type"] = contentType }

        let token = await session.accessToken
        guard let token else { throw APIError.unauthorized }
        var response = try await perform(request, token: token)
        if response.status == 401 {
            let renewed = try await session.refresh(rejected: token)
            response = try await perform(request, token: renewed)
        }
        guard (200..<300).contains(response.status) else {
            throw APIError.from(status: response.status, body: response.body)
        }
        return response
    }

    private func perform(_ request: HTTPRequest, token: String) async throws -> HTTPResponse {
        var request = request
        request.headers["Authorization"] = "Bearer \(token)"
        do {
            return try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.offline(String(describing: error))
        }
    }

    private func url(_ path: String, query: [String: String]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        }
        return components.url!
    }

    func decode<T: Decodable>(_ response: HTTPResponse) throws -> T {
        do {
            return try APICoding.decoder().decode(T.self, from: response.body)
        } catch {
            throw APIError.decoding("\(T.self)：\(error)")
        }
    }
}

extension UUID {
    /// 後端用小寫的 UUID（Swift 的 `uuidString` 是大寫）。
    public var apiString: String { uuidString.lowercased() }
}
