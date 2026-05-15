// KeychainService.swift
// co-money
// Secure storage for JWT tokens using iOS Keychain

import Foundation
import Security

// MARK: - KeychainService Overview
// 钥匙链服务 - iOS安全存储服务
//
// 这个类负责安全地存储敏感数据（如JWT令牌、用户凭证）到iOS Keychain中。
// Keychain是iOS提供的加密存储系统，所有数据都经过设备密钥加密。
//
// This service provides secure storage for sensitive data (JWT tokens, credentials, etc.)
// using iOS Keychain encryption. Keychain is the iOS-recommended way to store passwords,
// API keys, tokens, and other secrets. All data is encrypted with device-level keys.
//
// Design Pattern: Singleton
// 单例模式 - 整个应用只有一个KeychainService实例
// 确保所有地方都访问同一个Keychain存储
// The singleton pattern ensures all app code accesses the same Keychain storage,
// preventing accidental duplicates or inconsistencies.

final class KeychainService {
    // Singleton instance - 单例实例
    // 全应用共享的唯一实例
    // Shared across the entire app for consistent access
    static let shared = KeychainService()

    // Private initializer - 私有初始化器
    // 阻止创建多个实例，强制使用singleton
    // Prevents creating multiple instances, enforcing singleton pattern
    private init() {}

    // MARK: - Constants for Keychain Keys
    // Keychain键常量 - 用于标识存储的项目
    // 每个常量对应一个Keychain条目的唯一标识符
    // Each constant uniquely identifies an item in the Keychain

    private let accessTokenKey  = "co.money.access.token"       // JWT access token
    private let refreshTokenKey = "co.money.refresh.token"      // JWT refresh token for token renewal
    private let usernameKey     = "co.money.username"           // Stored login username
    private let passwordKey     = "co.money.password"           // Stored login password (optional)
    private let serverURLKey    = "co.money.server.url"         // User's custom server base URL

    // MARK: - Token Properties
    // 令牌属性 - 通过计算属性访问Keychain中的数据
    // These are computed properties that wrap load() and save() calls.
    // When you set accessToken = "xyz", it calls save(). When you get it, it calls load().
    // 使用计算属性实现透明的Keychain读写
    // Using computed properties makes Keychain access transparent to callers.

    /// Access token for API authentication
    /// API认证用的访问令牌，通常是短期有效的JWT
    /// This is the short-lived JWT token used to authenticate API requests
    var accessToken: String? {
        get { load(key: accessTokenKey) }
        // Setter: if newValue is not nil, save it; if nil, delete it
        // 新值非空时保存，为nil时删除
        set { newValue.map { save(key: accessTokenKey, value: $0) } ?? delete(key: accessTokenKey) }
    }

    /// Refresh token for obtaining new access tokens
    /// 用于获取新访问令牌的刷新令牌，通常是长期有效的JWT
    /// This is the long-lived JWT token used to obtain a new access token when it expires
    var refreshToken: String? {
        get { load(key: refreshTokenKey) }
        set { newValue.map { save(key: refreshTokenKey, value: $0) } ?? delete(key: refreshTokenKey) }
    }

    /// Stored username for login
    /// 登录用户名，用于提醒用户或自动填充登录表单
    /// Optional: stores the username to display or auto-fill on login screen
    var username: String? {
        get { load(key: usernameKey) }
        set { newValue.map { save(key: usernameKey, value: $0) } ?? delete(key: usernameKey) }
    }

    /// Stored password for login (optional)
    /// 登录密码，是否保存取决于用户偏好
    /// Optional: stores the password only if user enables "save password" feature
    var password: String? {
        get { load(key: passwordKey) }
        set { newValue.map { save(key: passwordKey, value: $0) } ?? delete(key: passwordKey) }
    }

    /// The user's chosen server base URL (e.g. "https://codai8.com").
    /// 用户选择的服务器基础URL，例如"https://codai8.com"
    /// Stored persistently so it survives app restarts and logouts.
    /// 持久保存，应用重启和注销后仍然存在
    var serverURL: String? {
        get { load(key: serverURLKey) }
        set { newValue.map { save(key: serverURLKey, value: $0) } ?? delete(key: serverURLKey) }
    }

    /// Convenience property to check if user is logged in
    /// 便利属性 - 检查用户是否已登录
    /// Returns true if an access token exists, false otherwise
    /// 如果存在访问令牌，返回true；否则返回false
    var isLoggedIn: Bool { accessToken != nil }

    // MARK: - Logout Helper
    // 注销辅助方法 - 清除所有令牌和凭证

    /// Clear all tokens and credentials when user logs out
    /// 用户注销时清除所有令牌和凭证
    /// This is called during logout to securely remove sensitive data
    /// 在注销期间调用，安全地删除敏感数据
    func clearTokens() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
        delete(key: usernameKey)
        delete(key: passwordKey)
    }

    // MARK: - Private Helpers
    // 私有辅助方法 - 直接与iOS Keychain进行交互
    // These functions handle the low-level Keychain API calls.
    // 这些函数处理与iOS Keychain的低级API调用。

    // MARK: Save to Keychain
    /// Save a string value to Keychain
    /// 将字符串值保存到Keychain
    ///
    /// iOS Keychain API:
    /// - kSecClass: 项目类型（密码类为kSecClassGenericPassword）
    /// - kSecAttrAccount: 项目的唯一标识符（在这里是我们的自定义键）
    /// - kSecValueData: 要存储的加密数据
    ///
    /// Flow:
    /// 1. Convert string to UTF-8 Data (Keychain only stores Data, not strings)
    ///    将字符串转换为UTF-8数据（Keychain只能存储Data）
    /// 2. Create query dictionary with Keychain parameters
    ///    使用Keychain参数创建查询字典
    /// 3. Delete any existing item with this key first (avoid duplicates)
    ///    先删除已有的相同键的项目（避免重复）
    /// 4. Add the new item
    ///    添加新项目
    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Query dictionary describes what we're storing
        // 查询字典描述我们要存储的内容
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,  // Type: generic password (most flexible)
            kSecAttrAccount: key,                        // Unique identifier for this item
            kSecValueData:   data                        // The actual encrypted data to store
        ]

        // Delete any existing item with this key to avoid duplicates
        // 删除具有此键的任何现有项目，以避免重复
        SecItemDelete(query as CFDictionary)

        // Add the new item
        // 添加新项目
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: Load from Keychain
    /// Load a string value from Keychain
    /// 从Keychain加载字符串值
    ///
    /// iOS Keychain API parameters:
    /// - kSecReturnData: 告诉Keychain返回实际数据（true）
    /// - kSecMatchLimit: kSecMatchLimitOne表示只返回一个匹配项
    ///
    /// Returns: String if found, nil if not found or error occurs
    /// 返回值：如果找到则返回String，否则返回nil
    private func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,  // Type: generic password
            kSecAttrAccount: key,                        // Search for this identifier
            kSecReturnData:  kCFBooleanTrue as Any,      // Return the actual data
            kSecMatchLimit:  kSecMatchLimitOne           // Return only one result
        ]

        var result: AnyObject?

        // SecItemCopyMatching: query Keychain for matching items
        // 返回值errSecSuccess表示成功找到并返回了数据
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }

        // Convert Data back to String
        // 将Data转换回String
        return String(data: data, encoding: .utf8)
    }

    // MARK: Delete from Keychain
    /// Delete a value from Keychain
    /// 从Keychain删除值
    ///
    /// This removes the item permanently when it's no longer needed
    /// 当不再需要时，这会永久删除该项目
    private func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,  // Type: generic password
            kSecAttrAccount: key                         // Identifier to delete
        ]

        // SecItemDelete: remove all matching items
        // 删除所有匹配的项目
        SecItemDelete(query as CFDictionary)
    }
}
