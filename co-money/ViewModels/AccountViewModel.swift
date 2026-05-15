// AccountViewModel.swift
// co-money

import Foundation

/// MARK: - AccountViewModel Overview (账户视图模型概述)
///
/// AccountViewModel manages shared account data and user invitations.
/// Shared accounts allow multiple users to collaborate on shared finances.
/// 账户视图模型管理共享账户数据和用户邀请。
/// 共享账户允许多个用户协作处理共享财务。
///
/// ┌─────────────────────────────────────────────────────────────┐
/// │  MVVM Data Flow for Accounts (账户数据流):                   │
/// │                                                               │
/// │  1. App launches, initialize AccountViewModel               │
/// │     应用启动，初始化 AccountViewModel                        │
/// │                                                               │
/// │  2. Call loadFromCache()                                     │
/// │     调用 loadFromCache()                                     │
/// │     ↓ (Instant, offline - 即时，离线)                       │
/// │  3. View displays cached accounts (if available)            │
/// │     视图显示缓存的账户（如果可用）                           │
/// │                                                               │
/// │  4. Call loadAccounts() (async network fetch)                │
/// │     调用 loadAccounts()（异步网络获取）                      │
/// │     ↓ (Fetches from /api/accounts/)                         │
/// │  5. Service makes HTTP GET request                           │
/// │     服务进行 HTTP GET 请求                                    │
/// │     ↓                                                         │
/// │  6. View automatically re-renders with updated accounts     │
/// │     视图自动使用更新的账户重新渲染                           │
/// │     (SwiftUI detects @Observable property changes)          │
/// │     (SwiftUI 检测 @Observable 属性更改)                      │
/// │     ↓                                                         │
/// │  7. ViewModel saves to cache (write-through)                │
/// │     ViewModel 保存到缓存（写穿）                             │
/// │     For offline support                                      │
/// │     用于离线支持                                             │
/// └─────────────────────────────────────────────────────────────┘
///
/// Key Responsibilities (关键责任):
/// 1. Load shared accounts for the current user
///    加载当前用户的共享账户
/// 2. Create new shared accounts
///    创建新的共享账户
/// 3. Delete shared accounts
///    删除共享账户
/// 4. Track pending invitations (for badge on Accounts tab)
///    跟踪待处理邀请（用于"账户"选项卡上的徽章）
/// 5. Cache-first pattern: offline support + instant load
///    缓存优先模式: 离线支持 + 即时加载
///
@Observable
final class AccountViewModel {
    /// MARK: - Observable Properties (可观察属性)
    /// These properties trigger SwiftUI re-renders when they change.
    /// 当这些属性更改时，它们会触发 SwiftUI 重新渲染。

    /// accounts: List of SharedAccount objects that the user belongs to
    /// Each shared account represents a collaborative budget or wallet
    /// 账户: 用户所属的 SharedAccount 对象列表
    /// 每个共享账户代表一个协作预算或钱包
    ///
    /// Example structure:
    /// [
    ///   SharedAccount(id: "acc-1", name: "Household Expenses", description: "Family budget"),
    ///   SharedAccount(id: "acc-2", name: "Trip to Tokyo", description: "2024 vacation")
    /// ]
    var accounts:              [SharedAccount] = []

    /// pendingInvitationCount: Number of pending invitations awaiting user response
    /// Used to show a badge on the Accounts tab (e.g., "4" in a red circle)
    /// Views check this to conditionally show badge: if count > 0, show red circle with count
    /// 待处理邀请计数: 等待用户响应的待处理邀请数
    /// 用于在"账户"选项卡上显示徽章（例如，红色圆圈中的"4"）
    /// 视图检查这个以有条件地显示徽章: 如果 count > 0，显示带有计数的红色圆圈
    var pendingInvitationCount = 0

    /// isLoading: Indicates if a network operation is in progress
    /// Views use this to show/hide loading spinners
    /// 正在加载: 指示网络操作是否正在进行中
    /// 视图使用此来显示/隐藏加载动画
    var isLoading              = false

    /// errorMessage: Stores the most recent error message
    /// Displayed in alert dialogs when operations fail
    /// 错误消息: 存储最新的错误消息
    /// 在操作失败时在警告对话框中显示
    var errorMessage:          String?

    /// MARK: - Dependencies (依赖项)

    /// service: Handles all account-related API calls
    /// - getAccounts(): Fetch all accounts for the user
    /// - createAccount(): Create a new shared account
    /// - deleteAccount(): Delete a shared account
    /// - getMyInvitations(): Fetch pending invitations
    /// 服务: 处理所有与账户相关的 API 调用
    /// - getAccounts(): 获取用户的所有账户
    /// - createAccount(): 创建新的共享账户
    /// - deleteAccount(): 删除共享账户
    /// - getMyInvitations(): 获取待处理邀请
    private let service = AccountService.shared

    // MARK: - Load from Server

    /// Fetch all shared accounts from the API
    /// Called when user needs fresh data (pull-to-refresh, view appeared, etc.)
    /// 从 API 获取所有共享账户
    /// 当用户需要新数据时调用（下拉刷新、视图出现等）
    ///
    /// Execution Flow (执行流程):
    /// 1. Set isLoading = true (show spinner)
    ///    设置 isLoading = true（显示加载动画）
    /// 2. Clear any previous error messages
    ///    清除任何先前的错误消息
    /// 3. Call service.getAccounts() (async network request to /api/accounts/)
    ///    调用 service.getAccounts()（异步网络请求到 /api/accounts/）
    /// 4. Update accounts property with response
    ///    使用响应更新 accounts 属性
    /// 5. Save to cache for offline support
    ///    保存到缓存以支持离线
    /// 6a. If successful: SwiftUI automatically re-renders with new accounts
    ///     如果成功: SwiftUI 自动使用新账户重新渲染
    /// 6b. If failed: Show error message
    ///     如果失败: 显示错误消息
    /// 7. Set isLoading = false (hide spinner)
    ///    设置 isLoading = false（隐藏加载动画）
    func loadAccounts() async {
        /// Start loading state
        /// 启动加载状态
        isLoading    = true
        errorMessage = nil  // Clear previous errors
                            // 清除先前的错误

        do {
            /// Fetch from API
            /// await: Wait for the async network request to complete
            /// 从 API 获取
            /// await: 等待异步网络请求完成
            accounts = try await service.getAccounts()


        } catch {
            /// Network or parsing error
            /// Provide human-readable error message
            /// 网络或解析错误
            /// 提供人类可读的错误消息
            errorMessage = error.localizedDescription
        }

        /// Stop loading (regardless of success or failure)
        /// 停止加载（无论成功还是失败）
        isLoading = false
    }

    /// Fetch the count of pending invitations for the user
    /// Used to update the badge on the Accounts tab
    /// 获取用户待处理邀请的计数
    /// 用于更新"账户"选项卡上的徽章
    ///
    /// Execution Flow (执行流程):
    /// 1. Silently call getMyInvitations() (no error handling)
    ///    静默调用 getMyInvitations()（无错误处理）
    /// 2. Filter for pending status
    ///    按待处理状态过滤
    /// 3. Update pendingInvitationCount
    ///    更新 pendingInvitationCount
    /// 4. SwiftUI automatically updates badge if visible
    ///    SwiftUI 自动更新徽章（如果可见）
    ///
    /// Error Handling (错误处理):
    /// Non-fatal: If network fails, simply don't update the count
    /// This avoids showing error alerts for a "nice to have" feature
    /// 非致命: 如果网络失败，根本不更新计数
    /// 这避免为"很高兴拥有"的功能显示错误警报
    func refreshPendingInvitations() async {
        /// Try to fetch invitations silently
        /// 尝试静默获取邀请
        /// Use optional binding to ignore errors
        /// 使用可选绑定忽略错误
        if let received = try? await service.getMyInvitations() {
            /// Filter to only pending invitations
            /// 仅过滤待处理的邀请
            pendingInvitationCount = received.filter { $0.status == .pending }.count
        }
        /// If error: do nothing (pendingInvitationCount stays the same)
        /// 如果错误: 执行任何操作（pendingInvitationCount 保持不变）
    }

    // MARK: - Create Account

    /// Create a new shared account
    /// 创建新的共享账户
    ///
    /// Purpose (目的):
    /// User creates a new shared budget. Other users can be invited to it.
    /// 用户创建新的共享预算。可以邀请其他用户。
    ///
    /// Parameters (参数):
    /// - name: Account name (e.g., "Trip to Japan 2024")
    ///   账户名称（例如，"2024年日本之旅"）
    /// - description: Optional longer description (e.g., "Summer vacation budget")
    ///   可选的较长描述（例如，"夏季假期预算"）
    ///
    /// Flow (流程):
    /// 1. Call service.createAccount(name:description:)
    ///    调用 service.createAccount(name:description:)
    /// 2. API returns the created SharedAccount with server-assigned ID
    ///    API 返回创建的 SharedAccount，具有服务器分配的 ID
    /// 3. Optimistically add to accounts list
    ///    乐观地添加到账户列表
    /// 4. SwiftUI automatically re-renders with new account
    ///    SwiftUI 自动使用新账户重新渲染
    /// 5. If error: display error message
    ///    如果出错: 显示错误消息
    func createAccount(name: String, description: String?) async {
        do {
            /// Call API to create account
            /// 调用 API 创建账户
            let account = try await service.createAccount(name: name, description: description)

            /// Optimistic update: add to local list immediately
            /// 乐观更新: 立即添加到本地列表
            /// So user sees the new account appear instantly
            /// 这样用户看到新账户立即出现
            accounts.append(account)

        } catch {
            /// Network or validation error
            /// 网络或验证错误
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete Account

    /// Delete a shared account by ID
    /// 通过 ID 删除共享账户
    ///
    /// Considerations (考虑):
    /// - Only the account owner can delete
    ///   仅账户所有者可以删除
    /// - Deleting removes all transactions in the account (backend handles cascade)
    ///   删除会移除账户中的所有交易（后端处理级联）
    /// - Other members lose access
    ///   其他成员失去访问权
    ///
    /// Flow (流程):
    /// 1. Call service.deleteAccount(id:)
    ///    调用 service.deleteAccount(id:)
    /// 2. If successful: remove from accounts list
    ///    如果成功: 从账户列表中移除
    /// 3. If error: display error message
    ///    如果出错: 显示错误消息
    func deleteAccount(id: String) async {
        do {
            /// Call API to delete
            /// 调用 API 删除
            try await service.deleteAccount(id: id)

            /// Optimistic update: remove from local list
            /// 乐观更新: 从本地列表中移除
            /// removeAll(where:) removes the account with matching ID
            /// removeAll(where:) 移除 ID 匹配的账户
            accounts.removeAll { $0.id == id }

        } catch {
            /// Network error or permission denied
            /// 网络错误或权限被拒绝
            errorMessage = error.localizedDescription
        }
    }
}
