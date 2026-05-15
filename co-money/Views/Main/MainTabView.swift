// MainTabView.swift
// co-money

import SwiftUI

/// MainTabView: 應用主層級的內容視圖，負責初始化和管理所有視圖模型
/// MainTabView: App's main content view, responsible for initializing and managing all view models
///
/// 架構角色 Architecture role:
/// - 主要目的是初始化三個核心 ViewModel (@State 管理生命週期)
///   Primary purpose: initialize three core ViewModels (@State manages lifecycle)
/// - 通過 .environment() 修飾符將 ViewModel 注入到整個視圖樹
///   Injects ViewModels into entire view tree via .environment() modifier
/// - 實現數據加載策略：快速本地加載 + 異步遠程更新
///   Implements data loading strategy: fast local load + async remote update
/// - 是 LoginView 和 HomeView 之間的過渡層
///   Acts as transition layer between LoginView and HomeView
/// - 使用 @Environment 讀取已經初始化的 AuthViewModel
///   Uses @Environment to read already-initialized AuthViewModel
///
/// 導航層級 Navigation hierarchy:
/// RootView (AppDelegate/AppState)
///   ↓
/// LoginView (if not authenticated) 或 MainTabView (if authenticated)
///   ↓
/// HomeView (with all environments set up)
struct MainTabView: View {
    /// @Environment 屬性包裝器 - 從環境中注入 AuthViewModel
    /// @Environment property wrapper - injects AuthViewModel from environment
    /// 此 ViewModel 由父視圖（通常是 RootView）初始化並注入
    /// This ViewModel is initialized and injected by parent view (usually RootView)
    /// 無需在此初始化，只需讀取並傳遞 (No need to initialize here, just read and pass)
    @Environment(AuthViewModel.self) private var authVM

    /// @State 屬性包裝器 - 初始化和管理 TransactionViewModel 的生命週期
    /// @State property wrapper - initializes and manages TransactionViewModel lifetime
    /// @State 確保此 ViewModel 在 MainTabView 存在期間保持活跃
    /// @State ensures this ViewModel stays alive as long as MainTabView exists
    /// 初始值在視圖首次創建時執行，之後不會重新初始化
    /// Initial value runs when view first created, not re-initialized after
    /// 交易管理相關功能：加載、創建、編輯交易
    /// Transaction management features: load, create, edit transactions
    @State private var txVM      = TransactionViewModel()

    /// @State 屬性包裝器 - AccountViewModel 生命週期管理
    /// @State property wrapper - manages AccountViewModel lifetime
    /// 賬戶管理功能：加載共享賬戶、邀請、成員管理
    /// Account management features: load shared accounts, invitations, member management
    @State private var accountVM = AccountViewModel()

    /// @State 屬性包裝器 - ProfileViewModel 生命週期管理
    /// @State property wrapper - manages ProfileViewModel lifetime
    /// 用戶資料管理：分類設置、默認貨幣、個人偏好
    /// Profile management: category settings, default currency, personal preferences
    @State private var profileVM = ProfileViewModel()

    var body: some View {
        /// HomeView 是實際的內容視圖，包含選項卡和主要 UI
        /// HomeView is the actual content view with tabs and main UI
        HomeView()
            /// .environment() 修飾符 - 在視圖樹中注入依賴項
            /// .environment() modifier - injects dependencies into view tree
            /// 任何後代視圖都可以用 @Environment 訪問這些 ViewModel
            /// Any descendant view can access these ViewModels via @Environment
            /// 這是 SwiftUI 的依賴注入方式，比傳遞構造參數更優雅
            /// This is SwiftUI's dependency injection pattern, more elegant than constructor params
            .environment(txVM)
            .environment(accountVM)
            .environment(profileVM)
            .environment(authVM)

            /// onAppear 修飾符 - 視圖首次出現時執行
            /// onAppear modifier - executes when view first appears
            /// 與 View lifecycle 綁定：
            /// Tied to View lifecycle:
            /// 1. View 構造完成
            /// 2. body 計算完成
            /// 3. SwiftUI 開始渲染視圖樹
            /// 4. onAppear 代碼執行 ← 我們在這裡
            /// 5. 視圖在屏幕上顯示
            /// onAppear 保證在主線程執行 (Guaranteed to run on main thread)

            /// task 修飾符 - 異步任務管理
            /// task modifier - async task management
            /// 與 onAppear 不同，task 可以運行異步代碼而無需顯式 Task { await ... }
            /// Unlike onAppear, task can run async code without explicit Task { await ... }
            /// task 還會在視圖消失時自動取消任務（清理資源）
            /// task also auto-cancels when view disappears (cleanup resources)
            .task {
                // 然後從伺服器獲取新鮮數據（成功時更新緩存）
                // Then fetch fresh data from server (updates cache on success)

                /// async let 語法 - 並行執行多個異步操作
                /// async let syntax - executes multiple async operations in parallel
                /// 每個 async let 會立即啟動（不等待上一個完成）
                /// Each async let starts immediately (doesn't wait for previous)
                /// 然後 await (a, b, c, d, e) 等待所有完成
                /// Then await (a, b, c, d, e) waits for all to complete
                /// 這比順序執行 await a; await b; ... 快得多
                /// Much faster than sequential: await a; await b; ...
                /// 時間複雜度：並行 O(max) vs 順序 O(sum)
                /// Time complexity: parallel O(max) vs sequential O(sum)
                async let a: () = txVM.loadAll()
                async let b: () = accountVM.loadAccounts()
                async let c: () = profileVM.loadProfile()
                async let d: () = accountVM.refreshPendingInvitations()
                // 個人帳戶交易不在此處預載 —— 等使用者滑到「個人」卡片時才 lazy load
                // Personal transactions are NOT pre-loaded here; they are lazy-loaded
                // in HomeView when the user swipes to the "個人" card.

                /// 等待所有啟動操作完成
                /// Wait for all startup operations to complete
                _ = await (a, b, c, d)
            }
    }
}
