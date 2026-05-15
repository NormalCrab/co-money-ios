// ProfileService.swift
// co-money
// 用户资料服务 | User Profile Service
// 管理用户配置文件的读写操作
// Manages user profile read and write operations

import Foundation

// MARK: - Profile Service
// 用户资料服务 | User Profile Service
// 单例模式，处理所有用户配置相关的API调用
// Singleton pattern, handles all user profile-related API calls
//
// 用户资料概念 | User Profile Concept:
// 存储用户的个人设置和偏好，如默认货币、默认共享账户等
// Stores user's personal settings and preferences, like default currency, default shared accounts
//
// 职责 | Responsibilities:
// 1. 获取用户资料 | Fetch user profile
// 2. 更新用户资料 | Update user profile
//
// HTTP 接口 | HTTP endpoints:
// GET    /profile/  - 获取用户资料 | Get user profile
// PATCH  /profile/  - 更新用户资料 (部分更新) | Update user profile (partial)
final class ProfileService {
    // MARK: Singleton Pattern
    // 确保全应用只有一个用户资料服务实例
    // Ensures only one profile service instance app-wide
    static let shared = ProfileService()
    private init() {}

    private let client = APIClient.shared

    // MARK: - Get Profile

    /// 获取用户资料 | Get user profile
    /// 获取当前登录用户的完整资料信息
    /// Get complete profile information of currently logged-in user
    ///
    /// 请求方法 | Request method:
    /// HTTP GET /profile/
    ///
    /// 响应格式兼容性 | Response format compatibility:
    /// 后端API的 /profile/ 可能返回多种格式：
    /// Backend API's /profile/ might return multiple formats:
    ///
    /// 格式1：直接返回单个Profile对象 | Format 1: Direct single Profile object
    /// {
    ///   "id": "user-123",
    ///   "username": "john",
    ///   "email": "john@example.com",
    ///   "default_currency": "USD",
    ///   "default_shared_accounts": ["acc1", "acc2"]
    /// }
    ///
    /// 格式2：DRF分页格式 | Format 2: DRF paginated format
    /// {
    ///   "count": 1,
    ///   "results": [{ Profile对象 | Profile object }]
    /// }
    ///
    /// 格式3：纯数组 | Format 3: Plain array
    /// [{ Profile对象 | Profile object }]
    ///
    /// 这可能是API设计不一致或版本差异导致的
    /// This might be due to API design inconsistency or version differences
    ///
    /// 我们使用优雅降级策略：
    /// We use graceful degradation strategy:
    /// 1. 先尝试直接Profile对象 | Try direct Profile object first
    /// 2. 如果失败，尝试分页格式 | If fails, try paginated format
    /// 3. 如果还是失败，尝试纯数组 | If still fails, try plain array
    /// 4. 最后一次尝试会抛出真实错误 | Last attempt will throw real error
    func getProfile() async throws -> Profile {
        // 尝试策略1：直接Profile对象 | Try strategy 1: Direct Profile object
        // 这是最简洁的格式，很多现代API使用这种方式
        // This is simplest format, many modern APIs use this
        if let single: Profile = try? await client.request(path: "/profile/") {
            return single
        }

        // 尝试策略2：DRF分页格式 | Try strategy 2: DRF paginated format
        // DRF是Django REST Framework，很多Django项目使用它
        // DRF is Django REST Framework, many Django projects use it
        // Some DRF setups wrap in a paginated list
        struct ProfilePage: Decodable { let results: [Profile] }
        if let page: ProfilePage = try? await client.request(path: "/profile/"),
           let first = page.results.first {
            return first
        }

        // 尝试策略3：纯数组 | Try strategy 3: Plain array
        // Try plain array
        if let arr: [Profile] = try? await client.request(path: "/profile/"),
           let first = arr.first {
            return first
        }

        // 所有策略都失败 - 让真实错误浮出来 | All strategies failed - let real error surface
        // Final attempt — let the real error surface
        // 这次不使用 try? 了，让APIError被抛出
        // This time don't use try?, let APIError be thrown
        return try await client.request(path: "/profile/")
    }

    // MARK: - Update Profile

    /// 更新用户资料 | Update user profile
    /// 更新用户的个人设置和偏好
    /// Update user's personal settings and preferences
    ///
    /// 请求方法 | Request method:
    /// HTTP PATCH /profile/
    ///
    /// PATCH 语义 | PATCH semantics:
    /// - PATCH 是部分更新，只更新提供的字段
    /// - PATCH is partial update, only updates provided fields
    /// - 未提供的字段保持不变
    /// - Unmodified fields remain unchanged
    /// - 与 PUT 不同，PUT 需要提供完整对象
    /// - Different from PUT, PUT requires complete object
    ///
    /// 请求体格式 | Request body format:
    /// {
    ///   "default_currency": "CNY",
    ///   "default_shared_accounts": ["account-id-1", "account-id-2"]
    /// }
    ///
    /// 更新场景 | Update scenarios:
    /// 1. 用户改变默认货币 | User changes default currency
    ///    如从 USD 改为 CNY | E.g., from USD to CNY
    /// 2. 用户设置默认的共享账户 | User sets default shared accounts
    ///    在事务列表中默认显示这些账户的交易 | Default display transactions from these accounts
    /// 3. 可以只更新其中一个字段 | Can update just one field
    ///    不需要同时提供两个 | Don't need to provide both
    ///
    /// 参数 | Parameters:
    /// - defaultCurrency: 默认货币代码 (可选) | Default currency code (optional)
    ///   例如："USD", "CNY", "EUR" | E.g.: "USD", "CNY", "EUR"
    /// - defaultSharedAccounts: 默认共享账户IDs列表 (可选) | Default shared account IDs (optional)
    ///   例如：["acc1", "acc2"] | E.g.: ["acc1", "acc2"]
    func updateProfile(defaultCurrency: String?, defaultSharedAccounts: [String]?) async throws -> Profile {
        // 构建请求参数字典 | Build request parameters dictionary
        var params: [String: Any] = [:]

        // 可选参数 - 如果提供，添加到参数中 | Optional parameters - add if provided
        if let currency = defaultCurrency {
            params["default_currency"] = currency
        }
        if let accounts = defaultSharedAccounts {
            params["default_shared_accounts"] = accounts
        }

        // 使用 JSONSerialization 而不是 client.encoder
        // Use JSONSerialization instead of client.encoder
        // 原因：params 字典包含混合类型 (String + Array)，
        // Reason: params dict contains mixed types (String + Array),
        // JSONSerialization 更容易处理任意的 JSON 结构
        // JSONSerialization handles arbitrary JSON structures more easily
        // client.encoder 通常用于编码遵循 Codable 的对象
        // client.encoder usually used to encode Codable objects
        let body = try JSONSerialization.data(withJSONObject: params)

        // 发送 PATCH 请求 | Send PATCH request
        // 服务器部分更新资料，返回更新后的完整Profile对象
        // Server partially updates profile, returns updated complete Profile object
        return try await client.request(path: "/profile/", method: "PATCH", body: body)
    }
}
