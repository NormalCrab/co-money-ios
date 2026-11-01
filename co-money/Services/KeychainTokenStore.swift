import Foundation
import MMCore
import Security

/// 把 token 存在 Keychain。
///
/// `kSecAttrAccessibleAfterFirstUnlock`：開機解鎖過一次之後，背景上傳時也讀得到（ios-design §3.3）。
final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let account = "tokens"

    /// - Parameter service: 依伺服器分開存，切換 staging / 正式環境時不會拿錯 token。
    init(service: String) {
        self.service = service
    }

    func load() -> AuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    func save(_ tokens: AuthTokens?) {
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        // 先更新、沒有才新增：不先刪掉舊的，寫入中途被殺掉或失敗時舊 token 還在
        // （refresh token 每次換發都會作廢上一張，遺失就會被登出）。
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else {
            if status != errSecSuccess { NSLog("Keychain 更新 token 失敗：\(status)") }
            return
        }
        let added = SecItemAdd(baseQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        if added != errSecSuccess { NSLog("Keychain 新增 token 失敗：\(added)") }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
