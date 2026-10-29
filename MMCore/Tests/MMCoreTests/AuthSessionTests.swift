import Foundation
import Testing
@testable import MMCore

@Suite("登入與 token 換發")
struct AuthSessionTests {
    @Test("登入後兩張 token 都存起來")
    func login() async throws {
        let (client, transport, store) = makeClient(tokens: nil) { _ in
            json(200, #"{"access": "A", "refresh": "R"}"#)
        }

        try await client.session.login(username: "alice", password: "pw")

        #expect(store.load() == AuthTokens(access: "A", refresh: "R"))
        #expect(transport.requests[0].bodyJSON["username"] as? String == "alice")
    }

    @Test("帳密錯誤給看得懂的訊息")
    func wrongPassword() async throws {
        let (client, _, store) = makeClient(tokens: nil) { _ in json(401, #"{"detail": "No active account"}"#) }

        await #expect(throws: APIError.client(status: 401, message: "帳號或密碼錯誤", fieldErrors: [:])) {
            try await client.session.login(username: "alice", password: "wrong")
        }
        #expect(store.load() == nil)
    }

    @Test("401 時換 token 再送一次，新的 refresh token 也要存（否則下次就被登出）")
    func refreshesOn401() async throws {
        let (client, transport, store) = makeClient { request in
            if request.fullPath == "/api/auth/login/refresh/" {
                return json(200, #"{"access": "access-2", "refresh": "refresh-2"}"#)
            }
            return request.headers["Authorization"] == "Bearer access-2" ? json(200, "[]") : json(401, "{}")
        }

        let ledgers = try await client.ledgers()

        #expect(ledgers.isEmpty)
        #expect(store.load() == AuthTokens(access: "access-2", refresh: "refresh-2"))
        #expect(transport.paths() == ["/api/v2/ledgers/", "/api/auth/login/refresh/", "/api/v2/ledgers/"])
        #expect(transport.requests[1].bodyJSON["refresh"] as? String == "refresh-1")
    }

    @Test("好幾個請求同時 401，只換一次 token")
    func singleRefresh() async throws {
        let (client, transport, _) = makeClient { request in
            if request.fullPath == "/api/auth/login/refresh/" {
                return json(200, #"{"access": "access-2", "refresh": "refresh-2"}"#)
            }
            return request.headers["Authorization"] == "Bearer access-2" ? json(200, "[]") : json(401, "{}")
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = try await client.ledgers() }
            }
            try await group.waitForAll()
        }

        #expect(transport.paths().filter { $0 == "/api/auth/login/refresh/" }.count == 1)
    }

    @Test("refresh token 被拒絕：登出，丟 unauthorized")
    func refreshRejected() async throws {
        let (client, _, store) = makeClient { request in
            request.fullPath == "/api/auth/login/refresh/"
                ? json(401, #"{"detail": "Token is blacklisted"}"#) : json(401, "{}")
        }

        await #expect(throws: APIError.unauthorized) { _ = try await client.ledgers() }
        #expect(store.load() == nil)
    }

    @Test("換 token 時沒網路：不登出，token 留著下次再換")
    func refreshOffline() async throws {
        struct Down: Error {}
        let (client, _, store) = makeClient { request in
            if request.fullPath == "/api/auth/login/refresh/" { throw Down() }
            return json(401, "{}")
        }

        await #expect(throws: APIError.self) { _ = try await client.ledgers() }
        #expect(store.load() != nil)
    }

    @Test("沒登入時不送請求")
    func notLoggedIn() async throws {
        let (client, transport, _) = makeClient(tokens: nil) { _ in json(200, "[]") }

        await #expect(throws: APIError.unauthorized) { _ = try await client.ledgers() }
        #expect(transport.requests.isEmpty)
    }

    @Test("從 access token 讀出使用者 id")
    func userId() async {
        let store = InMemoryTokenStore(AuthTokens(access: jwt(userId: 42), refresh: "r"))
        let session = AuthSession(baseURL: baseURL, transport: FakeTransport { _ in json(200, "{}") }, store: store)

        #expect(await session.userId == 42)
    }

    @Test("登出：通知後端並清掉 token；後端沒回應也照樣登出")
    func logout() async {
        struct Down: Error {}
        let (client, transport, store) = makeClient { _ in throw Down() }

        await client.session.logout()

        #expect(store.load() == nil)
        #expect(transport.paths() == ["/api/auth/logout/"])
    }
}
