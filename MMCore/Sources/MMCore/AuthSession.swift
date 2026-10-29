import Foundation

/// 存 token 的地方。app 用 Keychain（`kSecAttrAccessibleAfterFirstUnlock`，背景上傳時也讀得到），
/// 測試用 `InMemoryTokenStore`。
public protocol TokenStore: Sendable {
    func load() -> AuthTokens?
    func save(_ tokens: AuthTokens?)
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: AuthTokens?

    public init(_ tokens: AuthTokens? = nil) {
        self.tokens = tokens
    }

    public func load() -> AuthTokens? {
        lock.lock(); defer { lock.unlock() }
        return tokens
    }

    public func save(_ tokens: AuthTokens?) {
        lock.lock(); defer { lock.unlock() }
        self.tokens = tokens
    }
}

/// 登入狀態與 token 換發（ios-design §3.3）。
///
/// - refresh token 每次使用都會換一張新的，新的兩張都要存起來，否則下次就被登出。
/// - 同一時間只發一個 refresh 請求：好幾個 API 同時收到 401 時，大家等同一個結果。
///   後端的 2 分鐘寬限只是保險，不該靠它。
/// - refresh 遇到網路錯誤不登出（token 可能還是好的）；只有後端明確拒絕（401）才登出。
public actor AuthSession {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let store: TokenStore
    private var refreshTask: Task<String, Error>?

    public init(baseURL: URL, transport: HTTPTransport, store: TokenStore) {
        self.baseURL = baseURL
        self.transport = transport
        self.store = store
    }

    public var isLoggedIn: Bool { store.load() != nil }

    public var accessToken: String? { store.load()?.access }

    /// 目前登入的使用者 id，從 access token 裡讀出來（simplejwt 的 `user_id` claim）。
    /// 待上傳的資料綁定這個 id（§3.3：換帳號登入時不會送出別人的資料）。
    public var userId: Int? {
        store.load().flatMap { JWT.userId(in: $0.access) ?? JWT.userId(in: $0.refresh) }
    }

    public func login(username: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let response = try await post("api/auth/login/", body: body)
        guard response.status == 200 else {
            if response.status == 401 {
                throw APIError.client(status: 401, message: "帳號或密碼錯誤", fieldErrors: [:])
            }
            throw APIError.from(status: response.status, body: response.body)
        }
        store.save(try decodeTokens(response.body))
    }

    /// 登出：通知後端作廢 refresh token（失敗也沒關係），然後清掉手機上的 token。
    public func logout() async {
        if let tokens = store.load(),
           let body = try? JSONSerialization.data(withJSONObject: ["refresh": tokens.refresh]) {
            _ = try? await post("api/auth/logout/", body: body, access: tokens.access)
        }
        refreshTask?.cancel()
        refreshTask = nil
        store.save(nil)
    }

    /// 換一張新的 access token。
    ///
    /// - Parameter rejected: 剛剛被後端拒絕的 access token。如果在等待的期間已經有別人換好了
    ///   （目前的 token 不是它），直接回傳新的，不再換一次。
    public func refresh(rejected: String?) async throws -> String {
        if let rejected, let current = store.load()?.access, current != rejected {
            return current
        }
        if let task = refreshTask {
            return try await task.value
        }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let tokens = store.load() else { throw APIError.unauthorized }
        let body = try JSONSerialization.data(withJSONObject: ["refresh": tokens.refresh])
        let response: HTTPResponse
        do {
            response = try await post("api/auth/login/refresh/", body: body)
        } catch {
            throw APIError.offline(String(describing: error))
        }
        switch response.status {
        case 200:
            // 後端開了 ROTATE_REFRESH_TOKENS，回應裡會有新的 refresh token；
            // 沒有的話（後端設定被改掉）沿用舊的，至少不會被登出。
            let renewed = try decodeTokens(response.body, fallbackRefresh: tokens.refresh)
            store.save(renewed)
            return renewed.access
        case 400, 401:
            // refresh token 過期或被作廢（90 天沒用、在別處登出）。
            store.save(nil)
            throw APIError.unauthorized
        default:
            throw APIError.from(status: response.status, body: response.body)
        }
    }

    private func post(_ path: String, body: Data, access: String? = nil) async throws -> HTTPResponse {
        var headers = ["Content-Type": "application/json", "Accept": "application/json"]
        if let access { headers["Authorization"] = "Bearer \(access)" }
        return try await transport.send(HTTPRequest(
            method: "POST", url: baseURL.appendingPathComponent(path), headers: headers, body: body))
    }

    private func decodeTokens(_ body: Data, fallbackRefresh: String? = nil) throws -> AuthTokens {
        struct Payload: Decodable {
            var access: String
            var refresh: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body),
              let refresh = payload.refresh ?? fallbackRefresh
        else { throw APIError.decoding("登入回應缺少 token") }
        return AuthTokens(access: payload.access, refresh: refresh)
    }
}

/// 只讀 JWT 的內容，不驗證簽章（簽章是後端的事）。
enum JWT {
    static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func userId(in token: String) -> Int? {
        switch payload(of: token)?["user_id"] {
        case let id as Int: id
        case let id as String: Int(id)
        default: nil
        }
    }
}
