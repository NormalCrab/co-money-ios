// ProfileViewModel.swift
// co-money

import Foundation

/// MARK: - ProfileViewModel Overview (个人资料视图模型概述)
///
/// ProfileViewModel manages user profile settings, preferences, and categories.
/// This is responsible for personalizing the app experience (currency, accounts, categories).
/// 个人资料视图模型管理用户个人资料设置、首选项和类别。
/// 这负责个性化应用体验（货币、账户、类别）。
///
/// ┌─────────────────────────────────────────────────────────────┐
/// │  MVVM Data Flow for Profile (个人资料数据流):                │
/// │                                                               │
/// │  1. View appears (Profile screen)                            │
/// │     视图出现（个人资料屏幕）                                 │
/// │     ↓                                                         │
/// │  2. Call loadFromCache()                                     │
/// │     调用 loadFromCache()                                     │
/// │     ↓ (Instant, offline - 即时，离线)                       │
/// │  3. Display cached profile and categories                   │
/// │     显示缓存的个人资料和类别                                 │
/// │                                                               │
/// │  4. Call loadProfile() (async network fetch)                 │
/// │     调用 loadProfile()（异步网络获取）                       │
/// │     ↓ (Fetches /api/profile/ and /api/categories/)         │
/// │  5. Service makes concurrent API requests                   │
/// │     服务进行并发 API 请求                                    │
/// │     ↓                                                         │
/// │  6. View automatically updates with fresh data              │
/// │     视图自动使用新数据更新                                   │
/// │     (SwiftUI detects @Observable changes)                   │
/// │     (SwiftUI 检测 @Observable 更改)                          │
/// │     ↓                                                         │
/// │  7. ViewModel saves to cache (write-through)                │
/// │     ViewModel 保存到缓存（写穿）                             │
/// │                                                               │
/// │  8. User edits profile (currency, default accounts)         │
/// │     用户编辑个人资料（货币、默认账户）                       │
/// │     ↓                                                         │
/// │  9. updateDefaultCurrency() or updateDefaultAccounts()      │
/// │     调用 updateDefaultCurrency() 或 updateDefaultAccounts() │
/// │     ↓ (API call)                                             │
/// │  10. Profile updated on server and locally                  │
/// │     个人资料在服务器和本地更新                               │
/// │                                                               │
/// │  11. User manages categories (CRUD)                         │
/// │     用户管理类别（增删改查）                                 │
/// │     ↓                                                         │
/// │  12. createCategory() or deleteCategory()                   │
/// │     调用 createCategory() 或 deleteCategory()                │
/// │     ↓ (API call)                                             │
/// │  13. Category list automatically updated                    │
/// │     类别列表自动更新                                         │
/// └─────────────────────────────────────────────────────────────┘
///
/// Key Responsibilities (关键责任):
/// 1. Load and cache user profile (name, email, preferences)
///    加载和缓存用户个人资料（名称、电子邮件、首选项）
/// 2. Manage default currency (used in transaction creation)
///    管理默认货币（在交易创建中使用）
/// 3. Manage default shared accounts (preselected for new transactions)
///    管理默认共享账户（为新交易预先选择）
/// 4. Load and manage transaction categories
///    加载和管理交易类别
/// 5. Allow CRUD operations on categories (create, delete custom categories)
///    允许对类别的 CRUD 操作（创建、删除自定义类别）
/// 6. Retrieve username from Keychain for display
///    从 Keychain 检索用户名以供显示
///
@Observable
final class ProfileViewModel {
    /// MARK: - Observable Properties (可观察属性)
    /// These properties trigger SwiftUI re-renders when they change.
    /// 当这些属性更改时，它们会触发 SwiftUI 重新渲染。

    /// profile: The authenticated user's profile information
    /// Contains: username, email, default currency, default shared accounts
    /// 已认证用户的个人资料信息
    /// 包含: 用户名、电子邮件、默认货币、默认共享账户
    ///
    /// Structure (结构):
    /// {
    ///   "username": "alice@example.com",
    ///   "email": "alice@example.com",
    ///   "default_currency": "TWD",
    ///   "default_shared_accounts": ["acc-1", "acc-2"]
    /// }
    var profile:      Profile?

    /// categories: List of available transaction categories
    /// These are used to categorize expenses and income
    /// 可用交易类别列表
    /// 这些用于分类支出和收入
    ///
    /// Includes:
    /// - Predefined system categories (Groceries, Dining, Shopping, etc.)
    ///   预定义的系统类别（杂货、用餐、购物等）
    /// - User-created custom categories
    ///   用户创建的自定义类别
    var categories:   [Category] = []

    /// isLoading: Indicates if a network operation is in progress
    /// 指示网络操作是否正在进行中
    var isLoading     = false

    /// errorMessage: Stores the most recent error message
    /// 存储最新的错误消息
    var errorMessage: String?

    /// MARK: - Dependencies (依赖项)

    /// profileService: Handles profile-related API calls
    /// - getProfile(): Fetch user profile
    /// - updateProfile(): Update default currency or accounts
    /// 个人资料服务: 处理个人资料相关的 API 调用
    /// - getProfile(): 获取用户个人资料
    /// - updateProfile(): 更新默认货币或账户
    private let profileService = ProfileService.shared

    /// catService: Handles category API calls
    /// - getCategories(): Fetch all categories
    /// - createCategory(): Create custom category
    /// - deleteCategory(): Delete custom category
    /// 类别服务: 处理类别 API 调用
    /// - getCategories(): 获取所有类别
    /// - createCategory(): 创建自定义类别
    /// - deleteCategory(): 删除自定义类别
    private let catService     = CategoryService.shared

    /// keychain: Securely store/retrieve authentication tokens
    /// Also stores username for quick display without API call
    /// Keychain: 安全地存储/检索身份验证令牌
    /// 也存储用户名以便快速显示而无需 API 调用
    private let keychain       = KeychainService.shared

    /// MARK: - Computed Properties (计算属性)

    /// username: Retrieves the current user's username from Keychain
    /// Falls back to empty string if not available (shouldn't happen after login)
    /// 从 Keychain 检索当前用户的用户名
    /// 如果不可用，则回退到空字符串（登录后不应发生）
    ///
    /// Why from Keychain? (为什么来自 Keychain?)
    /// - Instantly available without API call
    ///   无需 API 调用即可立即获得
    /// - Stored during login, persists across app restarts
    ///   在登录期间存储，在应用重启后持续保存
    var username: String { keychain.username ?? "" }

    // MARK: - Load from Server

    /// Fetch user profile and categories from API
    /// Combines two concurrent requests for efficiency
    /// 从 API 获取用户个人资料和类别
    /// 结合两个并发请求以提高效率
    ///
    /// Execution Flow (执行流程):
    /// 1. Set isLoading = true (show spinner)
    ///    设置 isLoading = true（显示加载动画）
    /// 2. Clear any previous error messages
    ///    清除任何先前的错误消息
    /// 3. Start both API requests concurrently using async let
    ///    使用 async let 并发启动两个 API 请求
    /// 4. Wait for BOTH to complete
    ///    等待两者都完成
    /// 5. Update profile and categories properties
    ///    更新个人资料和类别属性
    /// 6. Save to cache for offline support
    ///    保存到缓存以支持离线
    /// 7. Set isLoading = false (hide spinner)
    ///    设置 isLoading = false（隐藏加载动画）
    func loadProfile() async {
        /// Start loading state
        /// 启动加载状态
        isLoading    = true
        errorMessage = nil

        /// async let: Start both requests in parallel
        /// async let: 并行启动两个请求
        /// Both run concurrently (faster than sequential)
        /// 两者并发运行（比顺序更快）
        async let p = profileService.getProfile()
        async let c = catService.getCategories()

        do {
            /// Wait for both results
            /// 等待两个结果
            /// If either fails, catch block handles the error
            /// 如果其中任何一个失败，catch 块处理错误
            let (prof, cats) = try await (p, c)

            /// Update observable properties (triggers SwiftUI re-render)
            /// 更新可观察属性（触发 SwiftUI 重新渲染）
            profile    = prof
            categories = cats


        } catch {
            /// Network or parsing error
            /// 网络或解析错误
            errorMessage = error.localizedDescription
        }

        /// Stop loading
        /// 停止加载
        isLoading = false
    }

    // MARK: - Profile Updates (个人资料更新)

    /// Update the user's default currency
    /// 更新用户的默认货币
    ///
    /// Purpose (目的):
    /// When creating new transactions, this currency is preselected.
    /// Helps users avoid repeatedly selecting the same currency.
    /// 创建新交易时，此货币是预选的。
    /// 帮助用户避免重复选择相同的货币。
    ///
    /// Parameter (参数):
    /// - currency: ISO 4217 currency code (e.g., "USD", "TWD", "EUR")
    ///   ISO 4217 货币代码（例如，"USD"、"TWD"、"EUR"）
    ///
    /// Flow (流程):
    /// 1. Call service.updateProfile(defaultCurrency:defaultSharedAccounts:)
    ///    调用 service.updateProfile(defaultCurrency:defaultSharedAccounts:)
    /// 2. Pass new currency and nil for accounts (unchanged)
    ///    为货币传递新的，为账户传递 nil（不变）
    /// 3. API returns updated profile
    ///    API 返回更新的个人资料
    /// 4. Update local profile property
    ///    更新本地个人资料属性
    /// 5. SwiftUI automatically re-renders
    ///    SwiftUI 自动重新渲染
    /// 6. If error: display error message
    ///    如果出错: 显示错误消息
    func updateDefaultCurrency(_ currency: String) async {
        do {
            /// Call API to update currency (leave accounts unchanged)
            /// 调用 API 更新货币（保持账户不变）
            /// defaultSharedAccounts: nil means "don't change this field"
            /// defaultSharedAccounts: nil 表示"不要更改此字段"
            profile = try await profileService.updateProfile(
                defaultCurrency:       currency,
                defaultSharedAccounts: nil
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Update the user's default shared accounts
    /// 更新用户的默认共享账户
    ///
    /// Purpose (目的):
    /// When creating new transactions, these accounts are preselected.
    /// Helps users avoid repeatedly selecting the same accounts.
    /// 创建新交易时，这些账户是预选的。
    /// 帮助用户避免重复选择相同的账户。
    ///
    /// Parameter (参数):
    /// - accountIds: Array of shared account IDs to set as defaults
    ///   要设置为默认值的共享账户 ID 数组
    ///
    /// Example (示例):
    /// updateDefaultAccounts(["household-budget", "shared-expenses"])
    ///
    /// Flow (流程):
    /// 1. Call service.updateProfile with new account list
    ///    使用新账户列表调用 service.updateProfile
    /// 2. Leave currency unchanged (pass nil)
    ///    保持货币不变（传递 nil）
    /// 3. API returns updated profile
    ///    API 返回更新的个人资料
    /// 4. Update local profile property
    ///    更新本地个人资料属性
    /// 5. SwiftUI automatically re-renders
    ///    SwiftUI 自动重新渲染
    /// 6. If error: display error message
    ///    如果出错: 显示错误消息
    func updateDefaultAccounts(_ accountIds: [String]) async {
        do {
            /// Call API to update accounts (leave currency unchanged)
            /// 调用 API 更新账户（保持货币不变）
            /// defaultCurrency: nil means "don't change this field"
            /// defaultCurrency: nil 表示"不要更改此字段"
            profile = try await profileService.updateProfile(
                defaultCurrency:       nil,
                defaultSharedAccounts: accountIds
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Category CRUD Operations (类别增删改查操作)

    /// Create a new custom transaction category
    /// 创建新的自定义交易类别
    ///
    /// Purpose (目的):
    /// Users can define custom categories beyond the predefined ones.
    /// Example: "Pet Care", "Hobby Supplies", etc.
    /// 用户可以定义预定义类别之外的自定义类别。
    /// 示例: "宠物护理"、"爱好用品"等。
    ///
    /// Parameters (参数):
    /// - name: Category name (e.g., "Coffee", "Gym")
    ///   类别名称（例如，"咖啡"、"健身房"）
    /// - icon: Optional emoji or icon string (e.g., "☕", "🏋️")
    ///   可选的 emoji 或图标字符串（例如，"☕"、"🏋️"）
    ///   Stored as plain text in database
    ///   存储为数据库中的纯文本
    ///
    /// Flow (流程):
    /// 1. Normalize icon: empty string → nil
    ///    规范化图标: 空字符串 → nil
    /// 2. Call service.createCategory(name:icon:)
    ///    调用 service.createCategory(name:icon:)
    /// 3. API returns the created category (with server-assigned ID)
    ///    API 返回创建的类别（带有服务器分配的 ID）
    /// 4. Optimistically add to categories list
    ///    乐观地添加到类别列表
    /// 5. SwiftUI automatically re-renders
    ///    SwiftUI 自动重新渲染
    /// 6. If error: display error message
    ///    如果出错: 显示错误消息
    func createCategory(name: String, icon: String?) async {
        do {
            /// Normalize empty icon to nil
            /// 规范化空图标为 nil
            let normalizedIcon = icon?.isEmpty == true ? nil : icon

            /// Call API to create category
            /// 调用 API 创建类别
            let cat = try await catService.createCategory(name: name, icon: normalizedIcon)

            /// Optimistic update: add to local list immediately
            /// 乐观更新: 立即添加到本地列表
            /// So user sees the new category appear instantly
            /// 这样用户看到新类别立即出现
            categories.append(cat)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a transaction category by ID
    /// 通过 ID 删除交易类别
    ///
    /// Considerations (考虑):
    /// - Only user-created categories can be deleted
    ///   只有用户创建的类别可以删除
    /// - Predefined categories cannot be deleted (backend enforces this)
    ///   预定义的类别不能删除（后端执行此操作）
    /// - Transactions with this category may become uncategorized
    ///   具有此类别的交易可能变为未分类
    /// - Backend may set affected transactions to a default category
    ///   后端可能将受影响的交易设置为默认类别
    ///
    /// Flow (流程):
    /// 1. Call service.deleteCategory(id:)
    ///    调用 service.deleteCategory(id:)
    /// 2. If successful: remove from categories list
    ///    如果成功: 从类别列表中移除
    /// 3. SwiftUI automatically re-renders
    ///    SwiftUI 自动重新渲染
    /// 4. If error: display error message
    ///    如果出错: 显示错误消息
    func deleteCategory(id: String) async {
        do {
            /// Call API to delete
            /// 调用 API 删除
            try await catService.deleteCategory(id: id)

            /// Optimistic update: remove from local list
            /// 乐观更新: 从本地列表中移除
            /// removeAll(where:) removes the category with matching ID
            /// removeAll(where:) 移除 ID 匹配的类别
            categories.removeAll { $0.id == id }

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
