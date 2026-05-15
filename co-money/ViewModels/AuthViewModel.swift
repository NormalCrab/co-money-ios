// AuthViewModel.swift
// co-money

import Foundation

/// MARK: - AuthViewModel Overview (认证视图模型概述)
///
/// AuthViewModel is responsible for managing authentication state and operations in the co-money app.
/// This is a critical component in the MVVM (Model-View-ViewModel) architecture.
///
/// 认证视图模型负责管理 co-money 应用中的认证状态和操作。
/// 这是 MVVM（Model-View-ViewModel）架构中的一个关键组件。
///
/// ┌─────────────────────────────────────────────────────────────┐
/// │  MVVM Data Flow (数据流向):                                  │
/// │                                                               │
/// │  View Layer (视图层)                                         │
/// │      ↓ (用户交互 User Actions)                              │
/// │  ViewModel Layer (本文件) ← @Observable 使 SwiftUI 观察变化  │
/// │      ↓ (调用服务 Calls Service)                             │
/// │  Service Layer (服务层: AuthService, KeychainService)       │
/// │      ↓ (网络请求 Network Request)                           │
/// │  API Backend (后端 API)                                      │
/// └─────────────────────────────────────────────────────────────┘
///
/// Key Concepts (关键概念):
/// 1. @Observable macro: Automatically tracks property changes and notifies SwiftUI views
///    @Observable 宏: 自动跟踪属性更改并通知 SwiftUI 视图
///
/// 2. ObservationTracking: When a View observes this ViewModel, SwiftUI automatically
///    re-renders when @Observable properties change (isLoggedIn, isLoading, errorMessage)
///    观察跟踪: 当 View 观察此 ViewModel 时，SwiftUI 会在 @Observable 属性更改时自动重新渲染
///
/// 3. Weak Self Capture: Prevents retain cycles (内存泄漏防护)
///    When NotificationCenter callback captures [weak self], it avoids keeping the ViewModel alive.
///    当 NotificationCenter 回调捕获 [weak self] 时，它避免保持 ViewModel 活动。
///
@Observable
final class AuthViewModel {
    /// MARK: - Observable Properties (可观察属性)
    /// These properties trigger SwiftUI view updates when they change.
    /// 当这些属性更改时，它们会触发 SwiftUI 视图更新。

    /// isLoggedIn: Tracks whether the user is currently authenticated
    /// When true, the app should display the main content; when false, show login screen.
    /// 用户当前是否已认证。为 true 时显示主要内容，为 false 时显示登录屏幕。
    var isLoggedIn: Bool

    /// isLoading: Indicates if a login/logout operation is in progress
    /// Views use this to show spinners or disable buttons during network requests.
    /// 指示登录/登出操作是否正在进行中。
    /// 视图使用此标志在网络请求期间显示加载动画或禁用按钮。
    var isLoading  = false

    /// errorMessage: Stores the most recent error message from failed auth operations
    /// Set to nil when starting a new operation (error recovery)
    /// 存储来自失败的认证操作的最新错误消息。
    /// 启动新操作时设置为 nil（错误恢复）。
    var errorMessage: String?

    /// MARK: - Dependencies (依赖项)
    /// Private services are injected via property initialization (Dependency Injection pattern)
    /// 私有服务通过属性初始化注入（依赖注入模式）

    /// authService: Handles login/logout network requests to the backend API
    /// 处理对后端 API 的登录/登出网络请求
    private let authService = AuthService.shared

    /// keychain: Securely stores and retrieves authentication tokens (native iOS security)
    /// - Stores tokens in iOS Keychain (encrypted storage)
    /// - Used for subsequent API requests with Bearer tokens
    /// - Persists across app restarts
    /// 安全地存储和检索身份验证令牌（本机 iOS 安全）
    /// - 在 iOS Keychain 中存储令牌（加密存储）
    /// - 用于使用 Bearer 令牌的后续 API 请求
    /// - 在应用重启后持久化
    private let keychain    = KeychainService.shared

    /// MARK: - Initialization (初始化)
    ///
    /// init(): Called once when the ViewModel is created
    /// Three key responsibilities:
    /// 1. Restore logged-in state from Keychain (offline support - 离线支持)
    /// 2. Register for session expiry notifications (监听会话过期通知)
    /// 3. Set up internal state
    init() {
        /// Restore authentication state from secure storage
        /// If tokens exist in Keychain, the user was previously logged in
        /// 从安全存储恢复认证状态。
        /// 如果 Keychain 中存在令牌，则用户之前已登录。
        isLoggedIn = keychain.isLoggedIn

        /// MARK: - NotificationCenter Listener (通知中心监听器)
        ///
        /// Purpose: Listen for session expiry events from other parts of the app
        /// 目的: 监听来自应用其他部分的会话过期事件
        ///
        /// Flow (流程):
        /// 1. When an API call returns 401 (Unauthorized), other services post .sessionExpired
        ///    当 API 调用返回 401（未授权）时，其他服务发布 .sessionExpired
        /// 2. NotificationCenter delivers this notification to the main thread
        ///    NotificationCenter 将此通知传递到主线程
        /// 3. This closure captures [weak self] to avoid creating a retain cycle
        ///    此闭包捕获 [weak self] 以避免创建强引用循环
        /// 4. We set isLoggedIn = false, which triggers View re-render
        ///    我们设置 isLoggedIn = false，这会触发 View 重新渲染
        ///
        /// Weak Self Explanation (弱引用解释):
        /// Without [weak self]: ViewModel → NotificationCenter → closure → ViewModel (循环！Cycle!)
        /// With [weak self]: If ViewModel is deallocated, self becomes nil and closure is safe
        /// 没有 [weak self]: ViewModel → NotificationCenter → 闭包 → ViewModel（循环！）
        /// 有 [weak self]: 如果 ViewModel 被释放，self 变为 nil，闭包是安全的
        NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: .main  // Execute on main thread (UI updates must be on main thread)
                          // 在主线程上执行（UI 更新必须在主线程上）
        ) { [weak self] _ in
            /// When session expires, immediately logout and update UI
            /// 当会话过期时，立即登出并更新 UI
            self?.isLoggedIn = false
        }
    }

    /// MARK: - Login Method (登录方法)
    ///
    /// func login(username: String, password: String) async
    /// Performs login operation and updates UI accordingly
    /// 执行登录操作并相应地更新 UI
    ///
    /// Execution Flow (执行流程):
    /// 1. Set isLoading = true (Show spinner on UI)
    ///    设置 isLoading = true（在 UI 上显示加载动画）
    /// 2. Clear any previous error messages
    ///    清除任何先前的错误消息
    /// 3. Call AuthService.login (async network call)
    ///    调用 AuthService.login（异步网络调用）
    /// 4a. If success: Set isLoggedIn = true (View re-renders, shows main content)
    ///     如果成功: 设置 isLoggedIn = true（View 重新渲染，显示主要内容）
    /// 4b. If failure: Capture error message (Show error alert to user)
    ///     如果失败: 捕获错误消息（向用户显示错误警告）
    /// 5. Set isLoading = false (Hide spinner)
    ///    设置 isLoading = false（隐藏加载动画）
    ///
    /// Async/Await Explanation (异步/等待解释):
    /// - async: This function is asynchronous (doesn't block the main thread)
    ///   这个函数是异步的（不会阻塞主线程）
    /// - await: Pause execution here until the async operation completes
    ///   暂停执行，直到异步操作完成
    /// - Main thread remains responsive during network request
    ///   网络请求期间主线程保持响应
    func login(username: String, password: String) async {
        /// UI State: Start loading
        /// UI 状态: 开始加载
        isLoading    = true
        errorMessage = nil  // Clear previous errors before new attempt
                            // 在新尝试之前清除先前的错误

        do {
            /// Try to authenticate with the backend
            /// Using await because AuthService.login is an async function
            /// 尝试使用后端进行身份验证
            /// 使用 await 因为 AuthService.login 是异步函数
            try await authService.login(username: username, password: password)

            /// If login succeeds, update state
            /// AuthService automatically saved tokens to Keychain
            /// 如果登录成功，更新状态
            /// AuthService 已自动将令牌保存到 Keychain
            isLoggedIn = true

        } catch {
            /// If login fails, store error message for display
            /// 如果登录失败，存储错误消息以供显示
            /// localizedDescription converts the error to human-readable text
            /// localizedDescription 将错误转换为人类可读的文本
            errorMessage = error.localizedDescription
        }

        /// UI State: Stop loading (regardless of success or failure)
        /// UI 状态: 停止加载（无论成功还是失败）
        isLoading = false
    }

    /// MARK: - Logout Method (登出方法)
    ///
    /// func logout() async
    /// Performs logout operation, always sets isLoggedIn = false
    /// 执行登出操作，始终设置 isLoggedIn = false
    ///
    /// Execution Flow (执行流程):
    /// 1. Try to notify the backend that user is logging out
    ///    尝试通知后端用户正在登出
    /// 2. If server unreachable: Fallback by clearing tokens locally
    ///    如果服务器无法访问: 通过在本地清除令牌回退
    /// 3. Always set isLoggedIn = false (Return to login screen)
    ///    始终设置 isLoggedIn = false（返回登录屏幕）
    ///
    /// Error Handling Strategy (错误处理策略):
    /// This is a "best-effort" logout. Network errors are silently ignored
    /// because the primary goal is to clear local state, which always succeeds.
    /// 这是一个"尽力而为"的登出。网络错误被静默忽略，
    /// 因为主要目标是清除本地状态，这总是成功的。
    func logout() async {
        let refreshToken = keychain.refreshToken

        /// Local logout is the source of truth for the app UI. Do it first so
        /// offline users return to LoginView immediately instead of waiting for
        /// the server logout request to time out.
        /// 本地登出是 UI 的單一真相來源：先清 token 並回登入頁，避免離線時卡住。
        keychain.clearTokens()
        errorMessage = nil
        isLoading = false
        isLoggedIn = false

        /// Server logout is best-effort. If it fails, the next login will get a
        /// fresh token pair anyway.
        /// server 登出只盡力執行；失敗也不影響下次登入重新取得 token。
        Task {
            await authService.notifyLogout(refreshToken: refreshToken)
        }
    }
}
