// AuthService.swift
// co-money
// 认证服务 | Authentication Service
// 管理登录、注册和登出的业务逻辑
// Manages login, registration, and logout business logic

import Foundation

// MARK: - Auth Service
// 认证服务 | Authentication Service
// 单例设计模式，提供全应用的身份验证功能
// Singleton design pattern, provides app-wide authentication functionality
//
// 职责 | Responsibilities:
// 1. 登录 - 验证用户名和密码，获取JWT令牌
//    Login - validate username and password, obtain JWT tokens
// 2. 注册 - 创建新用户账户
//    Register - create new user account
// 3. 登出 - 清除本地令牌和缓存
//    Logout - clear local tokens and cache
//
// 数据流 | Data Flow:
// 登录流程：
// Login flow:
// 用户输入(username, password) → AuthService.login() → APIClient.request()
// User input → APIClient.request()
// → HTTP POST /auth/login/ → 服务器验证凭据
// → Server validates credentials
// → 返回 {access_token, refresh_token} → KeychainService 保存令牌
// → Return tokens → KeychainService saves tokens
// → 令牌可用于后续所有API请求 (Authorization: Bearer <token>)
// → Tokens available for all subsequent API requests
final class AuthService {
    // MARK: Singleton Pattern
    // 确保全应用只有一个认证服务实例
    // Ensures only one authentication service instance app-wide
    static let shared = AuthService()
    private init() {}

    // MARK: Dependencies (依赖注入)
    // 依赖注入 | Dependency Injection
    // 注入 APIClient 和 KeychainService，便于测试和解耦
    // Inject APIClient and KeychainService for easier testing and decoupling
    private let client   = APIClient.shared
    private let keychain = KeychainService.shared

    // MARK: - Login

    /// 登录用户 | Login User
    /// async/await 模式 - 异步执行网络请求，不阻塞UI线程
    /// async/await pattern - executes network request asynchronously, doesn't block UI
    /// throws - 如果登录失败（无网络、错误凭据等）会抛出异常
    /// throws - throws if login fails (no network, invalid credentials, etc.)
    ///
    /// 登录流程 | Login flow:
    /// 1. 接收用户输入的用户名和密码
    ///    Receive username and password from user input
    /// 2. 编码为JSON: {"username": "user", "password": "pass"}
    ///    Encode to JSON
    /// 3. 发送POST请求到 /auth/login/
    ///    Send POST request to /auth/login/
    /// 4. 服务器验证凭据，返回JWT令牌对
    ///    Server validates, returns JWT token pair
    /// 5. 解码响应为 TokenPair 对象 (包含 access + refresh)
    ///    Decode response as TokenPair object
    /// 6. 保存令牌到安全的钥匙链存储
    ///    Save tokens to secure keychain storage
    /// 7. 保存用户名和密码用于自动重新登录（当refresh失效时）
    ///    Save username and password for auto re-login (when refresh expires)
    func login(username: String, password: String) async throws {
        // JSON 编码 | JSON encoding
        // client.encoder 是配置好的 JSONEncoder，将Swift对象转换为JSON数据
        // client.encoder is configured JSONEncoder, converts Swift objects to JSON data
        // 对于登录，只需要 username 和 password 字段
        // For login, only need username and password fields
        let body = try client.encoder.encode(["username": username, "password": password])

        // 发送POST请求 | Send POST request
        // 泛型 <TokenPair> 告诉client期望的响应类型
        // Generic <TokenPair> tells client the expected response type
        // APIClient 会自动：
        // APIClient automatically:
        // 1. 构建带完整URL的请求 | Build request with complete URL
        // 2. 发送HTTP请求 | Send HTTP request
        // 3. 解码JSON响应为 TokenPair | Decode JSON response as TokenPair
        let tokens: TokenPair = try await client.request(path: "/auth/login/", method: "POST", body: body)

        // 保存令牌到钥匙链 | Save tokens to keychain
        // 钥匙链是iOS中安全存储敏感数据的标准方式
        // Keychain is standard iOS mechanism for securely storing sensitive data
        // 存储在钥匙链中的数据受到加密保护，即使设备被盗也难以访问
        // Data stored in keychain is encrypted, difficult to access even if device is stolen
        keychain.accessToken  = tokens.access
        keychain.refreshToken = tokens.refresh

        // 保存用户名和密码 | Save username and password
        // 这些用于当 refresh_token 失效时的自动重新登录
        // These are used for automatic re-login when refresh_token expires
        // 虽然保存密码似乎不安全，但存储在iOS钥匙链中是可以接受的
        // Although saving password seems unsafe, storing in iOS keychain is acceptable
        // 它被加密保护，且应用无法访问其他应用的钥匙链数据
        // It's encrypted, and apps cannot access each other's keychain data
        keychain.username     = username
        keychain.password     = password   // stored for auto re-login when refresh token expires
    }

    // MARK: - Logout

    /// 登出用户 | Logout User
    /// 清除服务器端的会话并清理本地令牌
    /// Clear server-side session and clean up local tokens
    ///
    /// 登出流程 | Logout flow:
    /// 1. 检查是否有 refresh_token（需要保持连接才能登出）
    ///    Check if refresh_token exists (need connection to logout)
    /// 2. 发送POST请求到 /auth/logout/，包含 refresh_token
    ///    Send POST to /auth/logout/ with refresh_token
    /// 3. 服务器使 refresh_token 黑名单化（无法再使用）
    ///    Server blacklists refresh_token (cannot be used again)
    /// 4. 清除本地存储的所有令牌和用户凭据
    ///    Clear all locally-stored tokens and credentials
    /// 5. 清除所有缓存数据（如交易列表、类别等）
    ///    Clear all cached data (transactions, categories, etc.)
    func logout() async {
        let refresh = keychain.refreshToken
        keychain.clearTokens()
        await notifyLogout(refreshToken: refresh)
    }

    /// Best-effort server logout. Local auth state should already be cleared before this runs.
    /// 盡力通知 server 登出；本地登入狀態不應等待這個請求。
    func notifyLogout(refreshToken: String?) async {
        guard let refreshToken else { return }
        guard let body = try? client.encoder.encode(["refresh": refreshToken]) else { return }
        try? await client.requestVoid(path: "/auth/logout/", method: "POST", body: body)
    }

    // MARK: - Register

    /// 注册新用户 | Register New User
    /// 创建新的用户账户
    /// Create new user account
    ///
    /// 注册流程 | Registration flow:
    /// 1. 接收用户输入的用户名、密码和邮箱
    ///    Receive username, password, and email from user
    /// 2. 密码需要输入两次以验证拼写正确 (password + password2)
    ///    Password entered twice to verify spelling (password + password2)
    /// 3. 编码所有字段为JSON | Encode all fields as JSON
    /// 4. 发送POST请求到 /auth/register/
    ///    Send POST request to /auth/register/
    /// 5. 服务器验证输入，创建新用户 | Server validates, creates new user
    /// 6. 注册成功后，用户需要手动登录获取令牌
    ///    After registration, user needs to manually login to get tokens
    /// 7. 注册本身不返回令牌（设计决策），需要单独登录
    ///    Registration itself doesn't return tokens (design decision), need separate login
    func register(username: String, password: String, password2: String, email: String) async throws {
        // 准备注册参数 | Prepare registration parameters
        // password2 是服务器要求的密码确认字段
        // password2 is password confirmation field required by server
        // 通常用来验证用户拼写正确（两次输入相同）
        // Usually used to verify user spelled it correctly (both entries match)
        let params = [
            "username":  username,
            "password":  password,
            "password2": password2,
            "email":     email
        ]
        let body = try client.encoder.encode(params)

        // 发送注册请求 | Send registration request
        // API返回注册数据（如用户ID），但我们不需要使用它
        // API returns registration data (e.g., user ID), but we don't use it
        // 注册成功的关键是没有抛出异常 | Success is indicated by no exception being thrown
        // 类型推断：[String: String] 告诉编码器期望的响应格式
        // Type inference: [String: String] tells decoder the expected response format
        // 我们用 _ 忽略返回值，只关心是否成功 | We ignore return value with _, only care about success
        let _: [String: String] = try await client.request(path: "/auth/register/", method: "POST", body: body)
        // Returns 200 with registration data; we just want success
    }
}
