// APIClient.swift
// co-money
// Core HTTP client with JWT Bearer auth and automatic token refresh

import Foundation

// MARK: - API Error
// 错误枚举 | Error Enumeration
// 定义所有可能的 API 和网络错误类型
// Defines all possible API and network error types
enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case unauthorized
    case serverError(Int, String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:                   return "無效的 URL"
        case .noData:                       return "沒有收到資料"
        case .unauthorized:                 return "登入已過期，請重新登入"
        case .serverError(let c, let m):    return "伺服器錯誤 \(c): \(m ?? "Unknown")"
        case .decodingError(let e):         return "資料解析錯誤: \(e.localizedDescription)"
        case .networkError(let e):          return e.localizedDescription
        }
    }
}

// MARK: - Session Expired Notification
// 工作階段過期通知 | Session Expired Notification
// 当所有认证恢复尝试（刷新令牌 + 重新登录）失败时发送通知
// Posted when all auth recovery attempts (refresh + re-login) fail.
extension Notification.Name {
    /// Posted when all auth recovery attempts (refresh + re-login) fail.
    static let sessionExpired = Notification.Name("co.money.sessionExpired")
}

// MARK: - API Client
// API 客户端 | API Client
// 核心网络层 - 管理所有HTTP请求、JWT认证、令牌刷新和错误处理
// Core networking layer - manages all HTTP requests, JWT authentication, token refresh, and error handling
//
// 设计模式：单例 | Design Pattern: Singleton
// 使用单例确保全应用共享一个HTTP会话，保持令牌状态一致
// Uses singleton to ensure app-wide HTTP session sharing and consistent token state
final class APIClient {
    // MARK: Singleton Pattern (单例模式)
    // 通过静态 shared 属性提供全局访问点
    // Provides global access point via static shared property
    // 私有初始化方法防止多个实例被创建
    // Private init prevents multiple instances from being created
    static let shared = APIClient()
    private init() {}

    static let defaultServerURL = "https://codai8.com"

    /// API base URL built from the user's chosen server + "/api"
    /// 基础URL构建 | Base URL Construction
    /// 从用户选择的服务器 + "/api" 构建API基础URL
    /// Constructs API base URL from user-selected server + "/api"
    /// 从钥匙链读取服务器URL，添加 /api 路径前缀
    /// Reads server URL from keychain, appends /api path prefix
    var baseURL: String {
        let server = Self.upgradeToHTTPS(keychain.serverURL ?? Self.defaultServerURL)
        return server.hasSuffix("/") ? "\(server)api" : "\(server)/api"
    }

    /// Upgrade an http:// URL to https://. App Transport Security blocks plain HTTP,
    /// and the backend may return absolute pagination URLs (previous/next month URLs)
    /// with an http:// scheme that must be rewritten before we hand them to URLSession.
    /// 將 http:// 升級為 https://。ATS 會擋 HTTP，後端也可能回傳含 http:// 的分頁 URL，
    /// 必須在送進 URLSession 前改寫 scheme。
    static func upgradeToHTTPS(_ url: String) -> String {
        if url.lowercased().hasPrefix("http://") {
            return "https://" + url.dropFirst("http://".count)
        }
        return url
    }

    private let keychain = KeychainService.shared

    // MARK: - JSON Coders
    // JSON 编码器/解码器 | JSON Encoders/Decoders
    // Swift的Codable协议需要JSONDecoder和JSONEncoder来转换JSON数据和Swift对象
    // Swift's Codable protocol requires JSONDecoder and JSONEncoder to convert JSON data ↔ Swift objects
    //
    // 解码过程（JSON → Swift对象）:
    // Decoding process (JSON → Swift objects):
    // 1. 接收HTTP响应的JSON数据 | Receive JSON data from HTTP response
    // 2. JSONDecoder将JSON字符串转换为Date、String等原生类型 | JSONDecoder converts JSON to native types
    // 3. Codable协议自动将字典映射到结构体字段 | Codable protocol auto-maps dict to struct fields

    var decoder: JSONDecoder {
        let d = JSONDecoder()
        // 自定义日期解码策略 | Custom date decoding strategy
        // ISO8601 是国际标准日期格式 (如: 2024-03-24T10:30:00Z)
        // ISO8601 is international standard date format (e.g., 2024-03-24T10:30:00Z)
        //
        // 解码流程：
        // Decoding flow:
        // 1. 从JSON字符串读取日期 | Read date string from JSON
        // 2. 先尝试带小数秒的ISO8601格式 (2024-03-24T10:30:00.123Z)
        //    First try ISO8601 with fractional seconds (2024-03-24T10:30:00.123Z)
        // 3. 如果失败，降级到标准ISO8601格式 (2024-03-24T10:30:00Z)
        //    If fails, fall back to standard ISO8601 (2024-03-24T10:30:00Z)
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            // Try ISO8601 with fractional seconds first
            let isoFull = ISO8601DateFormatter()
            isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFull.date(from: str) { return date }
            // Fall back to standard ISO8601
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: str) { return date }
            // Django/DRF date fields often arrive as yyyy-MM-dd for transaction_date.
            let dateOnly = DateFormatter()
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let date = dateOnly.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return d
    }

    var encoder: JSONEncoder {
        let e = JSONEncoder()
        // 编码日期为ISO8601格式 | Encode dates as ISO8601 format
        // 编码过程（Swift对象 → JSON）:
        // Encoding process (Swift objects → JSON):
        // 1. 获取Date对象 | Get Date object
        // 2. 转换为标准ISO8601字符串 | Convert to standard ISO8601 string
        // 3. 包含在JSON请求体中 | Include in JSON request body
        e.dateEncodingStrategy = .iso8601
        return e
    }

    // MARK: - Generic Request
    // 通用请求方法 | Generic Request Method
    // 泛型<T: Decodable>允许返回任何遵循Codable协议的类型
    // Generic <T: Decodable> allows returning any type conforming to Codable protocol
    //
    // HTTP请求生命周期 | HTTP Request Lifecycle:
    // 1. buildRequest() - 构建URL请求 (设置HTTP方法、头、令牌)
    //    Build URL request (set HTTP method, headers, token)
    // 2. perform() - 发送请求到服务器，等待响应
    //    Send request to server, wait for response
    // 3. 检查401状态码 (未授权) - 令牌可能已过期
    //    Check 401 status code (unauthorized) - token might be expired
    // 4. refreshAccessToken() - 尝试刷新令牌或重新登录
    //    Try to refresh token or re-login
    // 5. decode() - 将响应JSON解析为Swift对象
    //    Parse response JSON into Swift object

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        // buildRequest() 构建HTTP请求
        // Constructs URLRequest with:
        // - 完整URL (baseURL + path)
        // - HTTP方法 (GET/POST/PATCH/DELETE)
        // - Authorization头 (Bearer <access_token>)
        // - Content-Type 和 Accept 头
        var urlRequest = try buildRequest(path: path, method: method, body: body)
        let (data, response) = try await perform(urlRequest)

        // JWT 令牌刷新逻辑 | JWT Token Refresh Logic
        // 如果收到401未授权响应，说明access_token已过期
        // If received 401 unauthorized, access_token is expired
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            // 步骤1：尝试使用refresh_token获取新的access_token
            // Step 1: Try to get new access_token using refresh_token
            // 这是JWT令牌刷新的标准做法
            // This is the standard JWT token refresh pattern
            if let newAccess = try? await refreshAccessToken() {
                // 更新内存中的令牌，准备重试
                // Update token in memory, prepare to retry
                keychain.accessToken = newAccess
                urlRequest.setValue("Bearer \(newAccess)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await perform(urlRequest)

                // 检查重试是否仍然失败
                // Check if retry still fails
                if let http2 = response2 as? HTTPURLResponse, http2.statusCode == 401 {
                    // refresh_token也失效了，会话完全过期
                    // refresh_token is also invalid, session fully expired
                    handleSessionExpired()
                    throw APIError.unauthorized
                }
                return try decode(data: data2, response: response2)
            } else {
                // refresh_token不存在或失败，清除所有令牌
                // refresh_token doesn't exist or failed, clear all tokens
                keychain.clearTokens()
                throw APIError.unauthorized
            }
        }

        return try decode(data: data, response: response)
    }

    /// Fetch a fully-qualified URL (used for `previousMonthUrl` / `nextMonthUrl` pagination)
    /// 获取完整URL | Fetch Full URL
    /// 用于分页导航 - 后端返回的 previousMonthUrl/nextMonthUrl 是完整URL，无需拼接baseURL
    /// Used for pagination navigation - backend returns complete previousMonthUrl/nextMonthUrl, no need to append baseURL
    ///
    /// 分页流程 | Pagination Flow:
    /// 1. 初始请求 /transactions/ 返回分页数据 + nextMonthUrl
    ///    Initial request to /transactions/ returns paginated data + nextMonthUrl
    /// 2. 用户点击"下一个月" | User clicks "next month"
    /// 3. 使用返回的nextMonthUrl直接请求，保留服务器的分页状态
    ///    Use returned nextMonthUrl directly, preserve server's pagination state
    func requestURL<T: Decodable>(_ fullURL: String) async throws -> T {
        guard let url = URL(string: Self.upgradeToHTTPS(fullURL)) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // 添加JWT令牌 | Add JWT token
        if let token = keychain.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await perform(req)

        // 同样的401处理逻辑 | Same 401 handling logic
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let newAccess = try? await refreshAccessToken() {
                keychain.accessToken = newAccess
                req.setValue("Bearer \(newAccess)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await perform(req)
                return try decode(data: data2, response: response2)
            } else {
                keychain.clearTokens()
                throw APIError.unauthorized
            }
        }
        return try decode(data: data, response: response)
    }

    /// Returns raw Data (after auth + refresh handling). Used when the caller wants to try multiple decode strategies.
    /// 返回原始数据 | Return Raw Data
    /// 当调用者想尝试多种解码策略时使用（某些API可能返回不同格式）
    /// Used when caller wants to try multiple decode strategies (some APIs might return different formats)
    /// 例如：某个endpoint可能返回分页格式或数组格式，调用者在获取原始Data后尝试两种解码
    /// Example: an endpoint might return paginated or array format, caller tries both decoding strategies
    func requestData(path: String, method: String = "GET") async throws -> Data {
        var urlRequest = try buildRequest(path: path, method: method, body: nil)
        let (data, response) = try await perform(urlRequest)

        // 401令牌刷新逻辑 | 401 token refresh logic
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let newAccess = try? await refreshAccessToken() {
                keychain.accessToken = newAccess
                urlRequest.setValue("Bearer \(newAccess)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await perform(urlRequest)
                try validateRawResponse(data: data2, response: response2)
                return data2
            } else {
                keychain.clearTokens()
                throw APIError.unauthorized
            }
        }
        try validateRawResponse(data: data, response: response)
        return data
    }

    /// 完整URL的原始数据请求 | Raw data request with full URL
    /// 用于分页（类似requestURL，但返回Data而非解码的对象）
    /// Used for pagination (similar to requestURL but returns Data instead of decoded object)
    func requestData(url: String) async throws -> Data {
        guard let fullURL = URL(string: Self.upgradeToHTTPS(url)) else { throw APIError.invalidURL }
        var req = URLRequest(url: fullURL)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = keychain.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await perform(req)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let newAccess = try? await refreshAccessToken() {
                keychain.accessToken = newAccess
                req.setValue("Bearer \(newAccess)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await perform(req)
                try validateRawResponse(data: data2, response: response2)
                return data2
            } else {
                keychain.clearTokens()
                throw APIError.unauthorized
            }
        }
        try validateRawResponse(data: data, response: response)
        return data
    }

    /// 无返回值的请求 | Void Request
    /// 用于DELETE、POST等不需要解析响应体的操作（如删除事务）
    /// Used for DELETE, POST operations that don't need response body parsing (e.g., delete transaction)
    ///
    /// 典型用法 | Typical usage:
    /// DELETE /transactions/123/ - 删除ID为123的事务，服务器返回204 No Content或204状态码
    /// DELETE /transactions/123/ - delete transaction with ID 123, server returns 204 No Content
    func requestVoid(path: String, method: String = "DELETE", body: Data? = nil) async throws {
        let urlRequest = try buildRequest(path: path, method: method, body: body)
        let (data, response) = try await perform(urlRequest)
        guard let http = response as? HTTPURLResponse else { return }
        // 检查4xx/5xx错误状态码 | Check for 4xx/5xx error status codes
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.serverError(http.statusCode, msg)
        }
    }

    // MARK: - Multipart Upload
    // 多部分表单上传 | Multipart Form Upload
    // 用于上传文件（如收据图片、音频）
    // Used to upload files (e.g., receipt images, audio)
    //
    // HTTP Content-Type: multipart/form-data
    // 这是表单编码，允许混合文本字段和文件数据
    // This is form encoding, allows mixing text fields and file data
    //
    // 分界符 (boundary) 用于分隔不同的表单字段
    // Boundary (分界符) separates different form fields
    // 例如：
    // Example:
    // --Boundary-UUID
    // Content-Disposition: form-data; name="file"; filename="receipt.jpg"
    // Content-Type: image/jpeg
    //
    // [二进制文件数据]
    // [binary file data]
    // --Boundary-UUID--

    func uploadMultipart<T: Decodable>(
        path: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        fieldName: String
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        // 生成唯一的分界符 | Generate unique boundary
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 设置 multipart/form-data 内容类型和分界符
        // Set multipart/form-data content type with boundary
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = keychain.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 手动构建 multipart 请求体 | Manually build multipart request body
        var body = Data()
        let nl = "\r\n"  // HTTP 行分隔符 | HTTP line separator

        // 分界符 + 文件头信息 | Boundary + file metadata
        body += "--\(boundary)\(nl)".data(using: .utf8)!
        body += "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\(nl)".data(using: .utf8)!
        body += "Content-Type: \(mimeType)\(nl)\(nl)".data(using: .utf8)!

        // 文件二进制数据 | File binary data
        body += fileData

        // 结束分界符 | Closing boundary
        body += "\(nl)--\(boundary)--\(nl)".data(using: .utf8)!
        req.httpBody = body

        let (data, response) = try await perform(req)
        return try decode(data: data, response: response)
    }

    // MARK: - Private Helpers
    // 私有帮助方法 | Private Helper Methods

    /// 构建 URLRequest | Build URLRequest
    /// 初始化HTTP请求，设置：
    /// Initialize HTTP request, set:
    /// 1. 完整URL (baseURL + path)
    /// 2. HTTP方法 (GET/POST/PATCH/DELETE)
    /// 3. 请求头 (Content-Type, Accept)
    /// 4. JWT Authorization 头 (Bearer <token>)
    private func buildRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        // Accept 头告诉服务器我们期望JSON响应
        // Accept header tells server we expect JSON response
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            // Content-Type 头告诉服务器请求体是JSON格式
            // Content-Type header tells server request body is JSON format
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // JWT Bearer 令牌认证 | JWT Bearer token authentication
        // Bearer 是OAuth 2.0标准的令牌类型
        // Bearer is OAuth 2.0 standard token type
        // 服务器使用此令牌识别用户身份
        // Server uses this token to identify user
        if let token = keychain.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// 处理会话过期 | Handle Session Expired
    /// 清除所有令牌并发送通知，通知应用导航回登录屏幕
    /// Clear all tokens and post notification to direct app back to login screen
    private func handleSessionExpired() {
        keychain.clearTokens()
        // 使用 @MainActor 确保通知在主线程发送（UI更新需要）
        // Use @MainActor to ensure notification posted on main thread (required for UI updates)
        Task { @MainActor in
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
        }
    }

    /// 执行 HTTP 请求 | Perform HTTP Request
    /// 低级方法，实际发送URLRequest并返回响应
    /// Low-level method that actually sends URLRequest and returns response
    /// 使用 URLSession.shared - 系统管理的共享会话
    /// Uses URLSession.shared - system-managed shared session
    /// async/await 语法使异步代码看起来同步，易于阅读
    /// async/await syntax makes async code look synchronous, easier to read
    private func perform(_ req: URLRequest) async throws -> (Data, URLResponse) {
        let method = req.httpMethod ?? "GET"
        let url    = req.url?.absoluteString ?? "(unknown)"
        print("[API] \(method) \(url)")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[API] \(status) \(url)")
            if let body = String(data: data, encoding: .utf8) {
                print("[API] body: \(body)")
            }
            return (data, response)
        } catch {
            print("[API] ERROR \(url) — \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    private func validateRawResponse(data: Data, response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.serverError(http.statusCode, msg)
        }
    }

    /// 解码 HTTP 响应 | Decode HTTP Response
    /// 解码流程：
    /// Decoding process:
    /// 1. 检查状态码是否为错误 (4xx/5xx)
    /// 2. 如果是，抛出服务器错误异常
    /// 3. 否则，使用 decoder 将JSON Data 转换为 Swift 对象
    private func decode<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.serverError(http.statusCode, msg)
        }
        do {
            // JSONDecoder.decode() 使用 Codable 协议自动映射JSON到Swift对象
            // JSONDecoder.decode() uses Codable protocol to auto-map JSON to Swift object
            // T.self 是类型参数，告诉解码器目标类型
            // T.self is type parameter, tells decoder the target type
            return try decoder.decode(T.self, from: data)
        } catch {
            // 捕获JSON解析错误（格式不匹配、缺少字段等）
            // Catch JSON parsing errors (format mismatch, missing fields, etc.)
            throw APIError.decodingError(error)
        }
    }

    /// JWT 令牌刷新逻辑 | JWT Token Refresh Logic
    /// 两步流程来恢复过期的会话：
    /// Two-step process to recover expired session:
    ///
    /// 步骤1：使用 refresh_token 获取新的 access_token
    /// Step 1: Use refresh_token to get new access_token
    /// POST /auth/login/refresh/ with refresh_token
    /// 返回新的 access_token（可能还有新的 refresh_token）
    /// Returns new access_token (might also return new refresh_token)
    ///
    /// 步骤2（如果步骤1失败）：使用保存的用户名/密码重新登录
    /// Step 2 (if step 1 fails): Re-login with saved username/password
    /// POST /auth/login/ with username + password
    /// 返回新的 access_token + refresh_token 对
    /// Returns new access_token + refresh_token pair
    ///
    /// 这个设计允许用户长期保持登录状态
    /// This design allows users to stay logged in long-term
    private func refreshAccessToken() async throws -> String {
        // 步骤1：尝试刷新令牌 | Step 1: Try token refresh
        if let refresh = keychain.refreshToken {
            if let url = URL(string: "\(baseURL)/auth/login/refresh/") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                // 将 refresh_token 编码为JSON | Encode refresh_token as JSON
                req.httpBody = try encoder.encode(["refresh": refresh])

                // 尝试刷新，忽略任何错误（如果失败就继续到步骤2）
                // Try refresh, ignore any errors (if fails, continue to step 2)
                if let (data, response) = try? await perform(req),
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let tokenResponse = try? decoder.decode(TokenRefreshResponse.self, from: data) {
                    // 后端可能轮换刷新令牌（安全最佳实践）
                    // Backend might rotate refresh_token (security best practice)
                    if let newRefresh = tokenResponse.refresh {
                        keychain.refreshToken = newRefresh
                    }
                    return tokenResponse.access
                }
            }
        }

        // 步骤2：刷新失败 → 尝试使用保存的用户名/密码重新登录
        // Step 2: Refresh failed → try re-login with saved credentials
        // 我们在初始登录时保存了这些凭据
        // We saved these credentials during initial login
        if let username = keychain.username, let password = keychain.password {
            let body = try encoder.encode(["username": username, "password": password])
            guard let url = URL(string: "\(baseURL)/auth/login/") else { throw APIError.invalidURL }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = body

            let (data, response) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw APIError.unauthorized
            }
            // 解码响应获得新的令牌对 | Decode response to get new token pair
            let tokens = try decoder.decode(TokenPair.self, from: data)
            keychain.accessToken  = tokens.access
            keychain.refreshToken = tokens.refresh
            return tokens.access
        }

        // 两步都失败 - 无法恢复会话 | Both steps failed - cannot recover session
        throw APIError.unauthorized
    }
}
