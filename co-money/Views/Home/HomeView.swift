// HomeView.swift
// co-money

import SwiftUI
import UIKit

// MARK: - Card Item

/// CardItem 數據結構 - 定義卡片的數據模型
/// CardItem data structure - defines data model for cards
/// 此結構用於在 TabView 中顯示賬戶卡片
/// This structure is used to display account cards in TabView
/// 遵循 Identifiable 協議使其能在 ForEach 中使用
/// Conforms to Identifiable for use in ForEach loops
struct CardItem: Identifiable {
    /// 唯一標識符 - 必須為 Identifiable 協議 (Unique identifier - required for Identifiable)
    /// ForEach 使用 id 來追蹤視圖列表中的哪一項對應哪個數據
    /// ForEach uses id to track which view corresponds to which data
    let id:            String

    /// 卡片標題 (Card title)
    let title:         String

    /// 卡片副標題，可選（例如："所有帳戶合計"）
    /// Optional subtitle (e.g., "所有帳戶合計")
    let subtitle:      String?

    /// 賬戶 ID：
    /// Account ID:
    /// - nil = 總計視圖 (total view)
    /// - "personal" = 個人記帳 (personal bookkeeping)
    /// - UUID = 共享賬戶 ID (shared account ID)
    let accountId:     String?

    /// 如果 accountId 不是 nil，此字段包含完整的共享賬戶對象
    /// If accountId is not nil, this field contains the full shared account object
    let sharedAccount: SharedAccount?

    /// 梯度色彩索引 - 用於選擇卡片背景漸變
    /// Gradient color index - used to select card background gradient
    /// 見 AccountSummaryCard.gradients 陣列
    /// See AccountSummaryCard.gradients array
    let colorIndex:    Int
}

// MARK: - Home View

/// HomeView: 應用的主要內容頁面，展示賬戶卡片和交易分析
/// HomeView: App's main content page showing account cards and transaction analysis
///
/// 主要責任 Key Responsibilities:
/// - 使用 TabView 實現卡片轉盤（帳戶切換）
///   Implement card carousel with TabView (account switching)
/// - 根據選定的卡片顯示對應的交易摘要和分析
///   Display transaction summary and analysis for selected card
/// - 提供導航到賬戶詳情、設置等的入口
///   Provide navigation to account details, settings, etc.
/// - 管理多個表單和工作表的呈現狀態
///   Manage presentation state of multiple sheets and forms
/// - 通過 @Environment 訪問 4 個不同的 ViewModel
///   Access 4 different ViewModels via @Environment
///
/// 導航層級 Navigation hierarchy:
/// MainTabView
///   ↓
/// HomeView ← 我們在這裡 (We are here)
///   ├─ NavigationStack
///   │  ├─ TabView (卡片轉盤 - card carousel)
///   │  │  └─ NavigationLink → AccountDetailView
///   │  ├─ ScrollView (分析部分 - analysis section)
///   │  └─ Toolbar (按鈕和菜單)
///   │     ├─ Settings → SettingsView
///   │     ├─ Add Transaction → AddTransactionView
///   │     ├─ Voice Input → VoiceInputView
///   │     └─ Receipt Capture → ReceiptCaptureView
struct HomeView: View {
    /// @Environment 屬性包裝器 - 注入 TransactionViewModel
    /// @Environment property wrapper - injects TransactionViewModel
    /// 獲取所有交易數據、摘要、分類分解
    /// Access all transaction data, summaries, category breakdowns
    @Environment(TransactionViewModel.self) private var txVM

    /// 注入 AccountViewModel - 獲取共享賬戶列表
    /// Inject AccountViewModel - access shared account list
    @Environment(AccountViewModel.self)     private var accountVM

    /// 注入 ProfileViewModel - 獲取分類和用戶偏好
    /// Inject ProfileViewModel - access categories and user preferences
    @Environment(ProfileViewModel.self)     private var profileVM

    /// 注入 AuthViewModel - 如果需要登出等
    /// Inject AuthViewModel - if logout needed
    @Environment(AuthViewModel.self)        private var authVM

    /// @State - 當前選定的卡片索引（0 = 總計, 1 = 個人, 2+ = 共享賬戶）
    /// @State - current selected card index (0=total, 1=personal, 2+=shared accounts)
    /// 這是主要的選擇狀態，驅動 TabView 的分頁和內容顯示
    /// This is the main selection state, drives TabView paging and content display
    /// 注意：selectedIndex 是位置索引，不是 ID（因為列表是動態的）
    /// Note: selectedIndex is positional index, not ID (list is dynamic)
    @State private var selectedIndex = 0

    /// @State - 控制手動交易輸入工作表的可見性
    /// @State - controls visibility of manual transaction input sheet
    @State private var showManual    = false

    /// @State - 控制語音輸入工作表的可見性
    /// @State - controls visibility of voice input sheet
    @State private var showVoice     = false

    /// @State - 控制收據掃描工作表的可見性
    /// @State - controls visibility of receipt scanning sheet
    @State private var showReceipt   = false

    /// @State - 控制設置工作表的可見性
    /// @State - controls visibility of settings sheet
    @State private var showSettings  = false

    /// 計算屬性：構建卡片列表
    /// Computed property: builds the card list
    /// 每次 accountVM.accounts 或相關數據變化時重新計算
    /// Recalculated whenever accountVM.accounts or related data changes
    /// 優勢：
    /// Advantages:
    /// - 卡片順序始終與當前賬戶列表同步
    ///   Card order always synced with current account list
    /// - 無需手動管理卡片狀態 (No manual card state management needed)
    /// - 添加/刪除賬戶會自動更新 UI
    ///   Adding/removing accounts automatically updates UI
    private func monthNavigationFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var cards: [CardItem] {
        var items: [CardItem] = [
            /// 第一張卡片：總計視圖（所有賬戶合計）
            /// First card: Total view (sum of all accounts)
            CardItem(id: "total",    title: "總帳戶", subtitle: "所有帳戶合計",
                     accountId: nil,        sharedAccount: nil, colorIndex: 0),

            /// 第二張卡片：個人記帳（只有個人交易）
            /// Second card: Personal bookkeeping (personal transactions only)
            CardItem(id: "personal", title: "個人",   subtitle: "個人記帳",
                     accountId: "personal", sharedAccount: nil, colorIndex: 1),
        ]

        /// 迴圈遍歷所有共享賬戶，添加到卡片列表
        /// Loop through all shared accounts and add to card list
        /// enumerated() 提供 (index, account) 元組
        /// enumerated() provides (index, account) tuples
        for (i, acc) in accountVM.accounts.enumerated() {
            items.append(CardItem(
                id: acc.id, title: acc.name,
                subtitle: acc.description,
                accountId: acc.id,
                sharedAccount: acc,
                colorIndex: i + 2 /// 顏色索引從 2 開始（0,1 已被總計和個人使用）
            ))
        }
        return items
    }

    /// Trigger the right endpoint for whichever card is currently selected.
    /// Re-fires when `selectedIndex` or `currentMonth` changes so the active
    /// card always shows data for the master month.
    /// 為目前選到的卡片觸發對應 endpoint：切卡片或切月時都會重打 API。
    private func loadDataForCard(at index: Int) {
        guard index < cards.count else { return }
        let card = cards[index]
        let activeMonth = txVM.currentMonth
        switch card.accountId {
        case nil:
            /// Total card uses the aggregated /transactions/ list which is
            /// loaded by loadAll() / loadTransactions() via toolbar nav.
            /// 總帳戶卡片用共用 /transactions/ 彙整資料，由 loadAll/切月時載入。
            break
        case "personal":
            if txVM.personalTransactions.isEmpty
                || txVM.personalCurrentMonth != activeMonth {
                Task { await txVM.loadPersonal(month: activeMonth) }
            }
        case let .some(id):
            let state = txVM.accountStates[id]
            if state == nil || state?.currentMonth != activeMonth {
                Task { await txVM.loadAccountTransactions(accountId: id, month: activeMonth) }
            }
        }
    }

    /// 計算屬性：月份顯示格式
    /// Computed property: month display format
    /// 將 "2025-03" 格式轉換為 "2025年3月" 格式
    /// Converts "2025-03" format to "2025年3月" format
    private var monthDisplay: String {
        guard let m = txVM.currentMonth else { return "本月" }
        /// split(separator:) 將字符串分成陣列 (Split string into array)
        let parts = m.split(separator: "-")
        if parts.count == 2, let y = Int(parts[0]), let mo = Int(parts[1]) {
            /// DateComponents - 組合日期的組成部分
            /// DateComponents - assemble date components
            var comps = DateComponents()
            comps.year = y
            comps.month = mo

            /// Calendar.current.date(from:) 從組件創建 Date 對象
            /// Calendar.current.date(from:) creates Date from components
            if let d = Calendar.current.date(from: comps) {
                /// formatted() 方法使用風格進行格式化
                /// formatted() method applies formatting styles
                return d.formatted(.dateTime.year().month(.abbreviated))
            }
        }
        return m
    }

    var body: some View {
        /// NavigationStack - 提供基於棧的導航容器
        /// NavigationStack - provides stack-based navigation container
        /// 允許 NavigationLink 推送新視圖到導航棧
        /// Allows NavigationLink to push new views to navigation stack
        NavigationStack {
            VStack(spacing: 0) {
                // ── 卡片轉盤 (Card Carousel) ────────────────────────────
                /// TabView 創建可分頁的視圖容器
                /// TabView creates pageable view container
                /// selection: $selectedIndex 綁定當前頁面索引
                /// selection: $selectedIndex binds the current page index
                /// 當用戶滑動卡片時，selectedIndex 自動更新
                /// When user swipes card, selectedIndex auto-updates
                /// 反之亦然：修改 selectedIndex 會改變顯示的卡片
                /// Vice versa: changing selectedIndex changes displayed card
                TabView(selection: $selectedIndex) {
                    /// ForEach 迴圈遍歷卡片列表
                    /// ForEach loop iterates through card list
                    /// Array(cards.enumerated()) 提供 (index, card) 元組
                    /// Array(cards.enumerated()) provides (index, card) tuples
                    /// id: \.element.id 使用卡片 ID 作為唯一標識
                    /// id: \.element.id uses card ID as unique identifier
                    /// 此 ID 用於保留視圖狀態（如果卡片被重新排序）
                    /// This ID preserves view state if cards are reordered
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        /// 獲取此卡片的交易摘要（收入、支出、結餘等）
                        /// Get transaction summary for this card (income, expense, balance, etc.)
                        /// summary() 是 TransactionViewModel 的方法
                        /// summary() is a TransactionViewModel method
                        let summary = txVM.summary(forAccountId: card.accountId)

                        /// NavigationLink 創建可點擊的導航入口
                        /// NavigationLink creates tappable navigation entry
                        /// 點擊卡片會推送到 AccountDetailView
                        /// Tapping card pushes to AccountDetailView
                        NavigationLink {
                            /// 目標視圖：AccountDetailView
                            /// Destination view: AccountDetailView
                            /// 傳遞卡片的上下文數據
                            /// Pass card context data
                            AccountDetailView(
                                cardTitle:  card.title,
                                accountId:  card.accountId,
                                account:    card.sharedAccount
                            )
                            /// 注入所有必要的 ViewModel 環境
                            /// Inject all necessary ViewModel environments
                            .environment(txVM)
                            .environment(accountVM)
                            .environment(profileVM)
                        } label: {
                            /// NavigationLink 的標籤是實際顯示的視圖
                            /// NavigationLink's label is the view being displayed
                            AccountSummaryCard(
                                title:        card.title,
                                subtitle:     card.subtitle,
                                summary:      summary,
                                /// 全部卡片都用同一個 currentMonth — 它是所有資料的單一真相來源
                                /// All cards share the single source of truth currentMonth.
                                currentMonth: txVM.currentMonth,
                                colorIndex:   card.colorIndex
                            )
                        }
                        .buttonStyle(.plain) /// 移除默認按鈕樣式 (Remove default button styling)
                        .tag(idx) /// 標籤用於 selection 綁定 (Tag for selection binding)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                    }
                }
                /// tabViewStyle 設置 TabView 的外觀
                /// tabViewStyle controls TabView appearance
                /// .page(indexDisplayMode: .always) 顯示分頁指示器（底部點）
                /// .page(indexDisplayMode: .always) shows page indicators (bottom dots)
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 178)
                // MARK: Lazy Load: 滑到卡片或切月時，從各自的權威 endpoint 載入
                // Lazy-load the data for whichever card the user is viewing.
                // - "personal" → /transactions/mine/
                // - 共用帳戶 ID → /accounts/{id}/transactions/ (per-account
                //   endpoint, avoids client-side filtering bugs when other
                //   users modify the same shared account)
                // - 總帳戶 (nil) → uses the aggregated /transactions/ list
                //   already fetched in loadAll().
                // Always passes the master currentMonth so per-card data stays
                // aligned with the month the user is actually viewing.
                // 滑到卡片時各自打自己的端點：個人 → /mine/、共用帳戶 → 帳戶
                // 自身端點。永遠用 txVM.currentMonth 確保月份同步。
                .onChange(of: selectedIndex) { _, newIndex in
                    loadDataForCard(at: newIndex)
                }
                // 切月後（currentMonth 變動），重新載入目前選到的 card，避免
                // 顯示舊月份資料。
                // After currentMonth changes, refetch the currently visible
                // card so it shows data for the new month.
                .onChange(of: txVM.currentMonth) { _, _ in
                    loadDataForCard(at: selectedIndex)
                }

                // ── 分析部分（可滾動）────────────────────────────────────
                // Analysis section (scrollable)
                /// ScrollView 允許垂直滾動內容
                /// ScrollView allows vertical scrolling of content
                /// 當內容超過屏幕高度時，用戶可以滾動
                /// When content exceeds screen height, user can scroll
                ScrollView {
                    /// 確保 selectedIndex 在有效範圍內
                    /// Ensure selectedIndex is within valid range
                    /// 防止數組越界錯誤
                    /// Prevents array out of bounds error
                    if selectedIndex < cards.count {
                        let card      = cards[selectedIndex]
                        /// 獲取當前選定卡片的交易摘要
                        /// Get transaction summary for currently selected card
                        let summary   = txVM.summary(forAccountId: card.accountId)
                        /// 獲取分類分解（按分類的支出分析）
                        /// Get category breakdown (expense analysis by category)
                        let breakdown = txVM.categoryBreakdown(
                            forAccountId: card.accountId,
                            categories:   profileVM.categories
                        )
                        let payerSpending = txVM.payerSpendingBreakdown(forAccountId: card.accountId)

                        VStack(spacing: 12) {
                            /// 顯示支出分析柱狀圖
                            /// Show spending analysis bar chart
                            SpendingAnalysisBar(summary: summary)

                            if !payerSpending.isEmpty {
                                PayerSpendingCard(items: payerSpending)
                            }

                            /// 條件性顯示分類分解卡片
                            /// Conditionally show category breakdown card
                            /// 只有當有分類數據時才顯示
                            /// Only show if there are categories to display
                            if !breakdown.isEmpty {
                                CategoryBreakdownCard(
                                    items: breakdown,
                                    summary: summary
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 20)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                voiceInputShortcut
            }
            .background(Color(.systemGroupedBackground)) /// iOS 系統背景色 (iOS system background)
            .navigationBarTitleDisplayMode(.inline)

            /// toolbar 修飾符 - 添加導航欄按鈕
            /// toolbar modifier - adds navigation bar buttons
            /// 允許在導航欄的不同位置放置按鈕和菜單
            /// Allows placing buttons and menus at different navbar locations
            .toolbar {
                // ── 左側：設置按鈕 ──────────────────────────────────────
                // Left: Settings button
                /// ToolbarItem(placement:) 指定按鈕的位置
                /// ToolbarItem(placement:) specifies button position
                /// .navigationBarLeading = 左側（與 Back 按鈕並排）
                /// .navigationBarLeading = left side (next to Back button)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        /// 點擊時顯示設置工作表
                        /// Show settings sheet on tap
                        showSettings = true
                    } label: {
                        /// ZStack 允許視圖重疊
                        /// ZStack allows views to overlap
                        /// 用於在齒輪圖標上放置通知徽章
                        /// Used to place notification badge on gear icon
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "gearshape")
                                .font(.subheadline)

                            /// 條件性顯示通知徽章
                            /// Conditionally show notification badge
                            /// 如果有待處理邀請，顯示橙色圓點
                            /// If there are pending invitations, show orange dot
                            if accountVM.pendingInvitationCount > 0 {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 4, y: -4) /// 微調位置 (Fine-tune position)
                            }
                        }
                    }
                }

                // ── 中心：月份導航 ────────────────────────────────────
                // Center: Month navigation
                /// placement: .principal = 居中（標題區域）
                /// placement: .principal = center (title area)
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        /// 上一月按鈕 — 統一切換共用月份，loadTransactions 內部
                        /// 會用同一個 currentMonth 同步重新載入個人交易。
                        /// Previous month — single source of truth: navigate shared
                        /// currentMonth; loadTransactions also refreshes personal for
                        /// the same month.
                        Button {
                            monthNavigationFeedback()
                            Task { await txVM.loadPreviousMonth() }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.bold())
                                .opacity(txVM.isChangingMonth ? 0.35 : 1)
                        }
                        .disabled(!txVM.hasPreviousMonth)

                        /// 月份顯示（可點擊返回當月）
                        /// Month display (tappable to return to current)
                        HStack(spacing: 6) {
                            Text(monthDisplay)
                                .font(.subheadline.bold())

                            if txVM.isChangingMonth {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        .frame(minWidth: 112) /// 固定最小寬度 (Fixed minimum width)

                        /// 下一月按鈕 — 同上，統一切共用月份。
                        /// Next month — same single-source-of-truth approach.
                        Button {
                            monthNavigationFeedback()
                            Task { await txVM.loadNextMonth() }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .opacity(txVM.isChangingMonth ? 0.35 : 1)
                        }
                        .disabled(!txVM.hasNextMonth)
                    }
                    .foregroundStyle(.primary)
                }

                // ── 右側：添加菜單 ─────────────────────────────────────
                // Right: Add menu
                /// placement: .primaryAction = 右側主操作按鈕
                /// placement: .primaryAction = right side primary action
                ToolbarItem(placement: .primaryAction) {
                    /// Menu - 提供按鈕點擊時顯示的選項列表
                    /// Menu - shows list of options on button tap
                    /// 點擊"+"按鈕會顯示 3 個選項
                    /// Tapping "+" button shows 3 options
                    Menu {
                        /// 選項 1：手動輸入
                        /// Option 1: Manual input
                        Button {
                            showManual = true
                        } label: {
                            /// Label 視圖結合文本和 SF Symbol 圖標
                            /// Label view combines text and SF Symbol icon
                            Label("手動輸入", systemImage: "square.and.pencil")
                        }

                        /// 選項 2：語音輸入
                        /// Option 2: Voice input
                        Button {
                            showVoice = true
                        } label: {
                            Label("語音輸入", systemImage: "mic.fill")
                        }

                        /// 選項 3：收據掃描
                        /// Option 3: Receipt scanning
                        Button {
                            showReceipt = true
                        } label: {
                            Label("收據辨識", systemImage: "doc.text.viewfinder")
                        }
                    } label: {
                        /// 菜單按鈕 (Menu button)
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }

            /// sheet 修飾符 - 顯示/隱藏工作表（模態視圖）
            /// sheet modifier - show/hide sheet (modal view)
            /// isPresented: $showSettings 綁定工作表可見性狀態
            /// isPresented: $showSettings binds sheet visibility state
            /// 當 showSettings = true 時，SettingsView 以工作表形式出現
            /// When showSettings=true, SettingsView appears as sheet
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(profileVM)
                    .environment(accountVM)
                    .environment(txVM)
                    .environment(authVM)
            }

            /// alert 修飾符 - 顯示警告對話框
            /// alert modifier - shows alert dialog
            /// isPresented: .constant(txVM.errorMessage != nil) 當有錯誤消息時顯示
            /// isPresented: .constant(...) shows when there's an error message
            /// .constant() 用於不想雙向綁定的情況
            /// .constant() used when two-way binding not needed
            .alert("錯誤", isPresented: .constant(txVM.errorMessage != nil)) {
                /// 警告按鈕 (Alert button)
                Button("確定") { txVM.errorMessage = nil }
            } message: {
                /// 警告消息內容 (Alert message content)
                Text(txVM.errorMessage ?? "")
            }
        }

        /// sheet 修飾符 - 手動交易輸入工作表
        /// sheet modifier - manual transaction input sheet
        .sheet(isPresented: $showManual) {
            /// 根據選定的卡片傳遞帳戶上下文
            /// Pass account context based on selected card:
            /// - 總計卡片（nil） → 使用偏好設置默認值
            ///   Total card (nil) → use profile defaults
            /// - 個人卡片（"personal"） → 沒有帳戶（真正個人）
            ///   Personal card ("personal") → no accounts
            /// - 共享帳戶卡片（UUID） → 預選該帳戶
            ///   Shared account card (UUID) → pre-select that account
            let selectedCard = selectedIndex < cards.count ? cards[selectedIndex] : nil
            let defaultIds: [String]? = {
                guard let card = selectedCard else { return nil }
                switch card.accountId {
                case nil:        return nil            // total → profile defaults
                case "personal": return []             // personal → no accounts
                default:         return [card.accountId!] // shared account
                }
            }()
            AddTransactionView(defaultAccountIds: defaultIds)
                .environment(txVM)
                .environment(accountVM)
                .environment(profileVM)
        }

        /// sheet 修飾符 - 語音輸入工作表
        /// sheet modifier - voice input sheet
        .sheet(isPresented: $showVoice) {
            VoiceInputView()
                .environment(txVM)
                .environment(accountVM)
                .environment(profileVM)
        }

        /// sheet 修飾符 - 收據掃描工作表
        /// sheet modifier - receipt scanning sheet
        .sheet(isPresented: $showReceipt) {
            ReceiptCaptureView()
                .environment(txVM)
                .environment(accountVM)
                .environment(profileVM)
        }
    }

    private var voiceInputShortcut: some View {
        HStack(spacing: 10) {
            shortcutButton(
                title: "語音",
                systemImage: "mic.fill",
                color: .accentColor
            ) {
                showVoice = true
            }

            shortcutButton(
                title: "相機",
                systemImage: "camera.fill",
                color: .orange
            ) {
                showReceipt = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    private func shortcutButton(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: color.opacity(0.24), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Account Summary Card

/// AccountSummaryCard: 顯示單個賬戶摘要的卡片組件
/// AccountSummaryCard: Card component showing individual account summary
///
/// 責任 Responsibilities:
/// - 顯示賬戶名稱、副標題、月份
///   Display account name, subtitle, month
/// - 展示結餘（支持多貨幣）
///   Show balance (supports multi-currency)
/// - 顯示收入和支出數字
///   Display income and expense figures
/// - 應用漸變背景色和陰影
///   Apply gradient background and shadow
/// - 提供視覺提示（"向右箭頭"）表示可點擊
///   Provide visual hint (right arrow) indicating tappable
///
/// 設計模式 Design patterns:
/// - 容器視圖：將多個小組件組合成一個可重用的卡片
///   Container view: combines multiple small components into reusable card
/// - 計算屬性用於梯度和格式化邏輯
///   Computed properties for gradient and formatting logic
struct AccountSummaryCard: View {
    /// 卡片標題 (Card title)
    let title:        String

    /// 卡片副標題 (Card subtitle)
    let subtitle:     String?

    /// 交易摘要數據（由 HomeView 傳遞）
    /// Transaction summary data (passed by HomeView)
    let summary:      TransactionSummary

    /// 當前月份字符串 (Current month string)
    let currentMonth: String?

    /// 用於選擇梯度顏色對的索引
    /// Index for selecting gradient color pair
    let colorIndex:   Int

    /// 靜態屬性：定義可用的梯度顏色對
    /// Static property: defines available gradient color pairs
    /// 每個賬戶使用不同的梯度以提高視覺區分
    /// Each account uses different gradient for visual distinction
    /// 索引循環回用：如果有超過 8 個賬戶，循環回到第一個梯度
    /// Index loops: if more than 8 accounts, cycles back to first gradient
    private static let gradients: [(Color, Color)] = [
        (.blue,   .purple),   // 0 total
        (.teal,   .cyan),     // 1 personal
        (.pink,   .orange),   // 2
        (.indigo, .blue),     // 3
        (.green,  .teal),     // 4
        (.orange, .red),      // 5
        (.purple, .pink),     // 6
        (.mint,   .green),    // 7
    ]

    /// 計算屬性：根據索引選擇並應用梯度
    /// Computed property: selects and applies gradient based on index
    /// LinearGradient 創建從一個顏色到另一個顏色的線性過渡
    /// LinearGradient creates linear transition from one color to another
    /// startPoint: .topLeading 和 endPoint: .bottomTrailing 定義方向
    /// startPoint and endPoint define gradient direction
    private var gradient: LinearGradient {
        let (c1, c2) = Self.gradients[colorIndex % Self.gradients.count]
        /// % 運算符進行循環索引（modulo）
        /// % operator loops the index (modulo)
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 計算屬性：格式化月份顯示
    /// Computed property: formats month display
    /// 將 "2025-03" 轉換為 "Mar 2025" 或類似格式
    /// Converts "2025-03" to "Mar 2025" or similar format
    private var monthDisplay: String {
        guard let m = currentMonth else { return "" }
        let parts = m.split(separator: "-")
        if parts.count == 2, let y = Int(parts[0]), let mo = Int(parts[1]) {
            var comps = DateComponents()
            comps.year = y
            comps.month = mo
            if let d = Calendar.current.date(from: comps) {
                return d.formatted(.dateTime.year().month(.abbreviated))
            }
        }
        return m
    }

    var body: some View {
        /// VStack 垂直堆疊視圖 - 所有內容從上到下排列
        /// VStack - stacks all content vertically
        /// alignment: .leading 將所有子視圖左對齐
        /// alignment: .leading left-aligns all children
        /// spacing: 0 移除默認間距，手動控制以獲得精確佈局
        /// spacing: 0 removes default spacing for precise layout
        VStack(alignment: .leading, spacing: 0) {
            // ── 標題行 (Header row) ──────────────────────────────────
            HStack(alignment: .top) {
                /// 左側：標題和副標題
                /// Left: title and subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)

                    /// 條件性顯示副標題
                    /// Conditionally show subtitle
                    if let sub = subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1) /// 單行，超出截斷 (Single line, truncate if too long)
                    }
                }
                Spacer() /// 將左右內容分開 (Space between left and right content)

                /// 右側：月份徽章
                /// Right: month badge
                if !monthDisplay.isEmpty {
                    Text(monthDisplay)
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2)) /// 半透明白色背景
                        .clipShape(Capsule()) /// 藥丸形狀 (Pill shape)
                }
            }

            Spacer() /// 推動內容向下 (Push content down)

            // ── 結餘 - 主要貨幣大字體，其他在下方列出
            // Balance - primary currency large, others listed below
            VStack(alignment: .leading, spacing: 2) {
                Text("結餘")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))

                /// HStack 水平堆疊：符號 + 金額
                /// HStack - stack symbol + amount horizontally
                /// alignment: .firstTextBaseline 對齐文字基線（數字看起來齊整）
                /// alignment: .firstTextBaseline aligns text baselines neatly
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    /// +/- 符號 (Plus/minus sign)
                    Text(summary.primary.balance >= 0 ? "+" : "-")
                        .font(.headline.bold())
                        .foregroundStyle(.white.opacity(0.9))

                    /// 金額文本 - 大型、粗體、圓形數字字體
                    /// Amount text - large, bold, rounded digit font
                    Text(summary.primary.balanceText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5) /// 如果超寬，允許縮放至 50%
                        .lineLimit(1) /// 防止換行 (Prevent line break)
                }

                // ── 多貨幣支持 (Multi-currency support) ──────────────────
                /// 如果有多個貨幣，列出其他貨幣
                /// If multi-currency, list additional currencies
                if summary.isMultiCurrency {
                    /// ForEach 迴圈遍歷除第一個（主）貨幣外的所有貨幣
                    /// ForEach loops through all currencies except first (primary)
                    /// dropFirst() 跳過第一個元素 (Skip first element)
                    ForEach(summary.currencies.dropFirst()) { cur in
                        HStack(spacing: 4) {
                            Text(cur.balance >= 0 ? "+" : "-")
                                .font(.caption.bold())
                            Text(cur.balanceText)
                                .font(.caption.bold().monospacedDigit())
                        }
                        .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            Spacer().frame(height: 6) /// 固定間距 (Fixed spacing)

            // ── 收入 / 支出 - 主要貨幣；其他內聯顯示
            // Income / Expense - primary currency; others shown inline
            HStack(spacing: 16) {
                /// 收入部分 (Income section)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                        Text("收入")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.8))

                    /// 主要貨幣的收入 (Primary currency income)
                    Text(summary.primary.incomeText)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.white)

                    /// 多貨幣：列出其他貨幣的收入
                    /// Multi-currency: list other currencies' income
                    if summary.isMultiCurrency {
                        ForEach(summary.currencies.dropFirst().filter { $0.income > 0 }) { cur in
                            Text(cur.incomeText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                /// 支出部分 (Expense section)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption)
                        Text("支出")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.8))

                    /// 主要貨幣的支出 (Primary currency expense)
                    Text(summary.primary.expenseText)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.white)

                    /// 多貨幣：列出其他貨幣的支出
                    /// Multi-currency: list other currencies' expense
                    if summary.isMultiCurrency {
                        ForEach(summary.currencies.dropFirst().filter { $0.expense > 0 }) { cur in
                            Text(cur.expenseText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                Spacer() /// 推動箭頭到右邊 (Push arrow to right)

                // ── "可點擊"提示 ("Tappable" hint) ──────────────────────
                /// 向右箭頭表示這是可點擊的導航元素
                /// Right arrow indicates this is a tappable navigation element
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity) /// 卡片填滿水平空間 (Card fills horizontal space)
        .frame(height: 152) /// 固定較小高度，讓下方資訊更早出現
        .background(gradient) /// 應用梯度背景 (Apply gradient background)
        .clipShape(RoundedRectangle(cornerRadius: 20)) /// 圓角矩形 (Rounded rectangle)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6) /// 投影效果 (Drop shadow)
    }
}

// MARK: - Payer Spending Card

struct PayerSpendingCard: View {
    let items: [PayerSpendingItem]

    private var maxTotal: Double {
        items.map(\.total).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.blue)
                Text("成員花費")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(items.prefix(4)) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text(amountText(for: item))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.14))
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue)
                                        .frame(width: barWidth(for: item, in: geo.size.width))
                                }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func amountText(for item: PayerSpendingItem) -> String {
        item.perCurrency
            .map { AmountFormatter.format($0.amount, currency: $0.currency) }
            .joined(separator: " / ")
    }

    private func barWidth(for item: PayerSpendingItem, in availableWidth: CGFloat) -> CGFloat {
        guard maxTotal > 0 else { return 0 }
        return max(0, availableWidth * CGFloat(item.total / maxTotal))
    }
}

// MARK: - Spending Analysis Bar

/// SpendingAnalysisBar: 顯示支出與收入比例的分析柱狀圖
/// SpendingAnalysisBar: Shows spending-to-income ratio as analysis bar chart
///
/// 功能 Features:
/// - 支持多貨幣顯示（每個貨幣一條柱子）
///   Multi-currency display (one bar per currency)
/// - 根據支出率改變顏色：綠色（低）→ 橙色（中）→ 紅色（高）
///   Color changes with spend ratio: green (low) → orange (medium) → red (high)
/// - 使用 GeometryReader 根據可用空間計算柱子寬度
///   Uses GeometryReader to calculate bar width based on available space
/// - 使用 spring 動畫使柱子平滑增長
///   Uses spring animation for smooth bar growth
///
/// 設計模式 Design patterns:
/// - 使用 @ViewBuilder（隱含）組合複雜佈局
///   Uses @ViewBuilder (implicit) to compose complex layouts
/// - 使用 filter 和 dropFirst 控制顯示哪些貨幣
///   Uses filter and dropFirst to control which currencies display
struct SpendingAnalysisBar: View {
    /// 交易摘要數據 (Transaction summary data)
    let summary: TransactionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本月花費分析")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)

            // ── 每個貨幣一條柱 (One bar per currency) ──────────────────
            /// 迴圈遍歷有收入或支出的貨幣
            /// Loop through currencies with income or expense
            /// filter { $0.income > 0 || $0.expense > 0 } 移除空貨幣行
            /// filter removes empty currency rows
            ForEach(summary.currencies.filter { $0.income > 0 || $0.expense > 0 }) { cur in
                VStack(alignment: .leading, spacing: 5) {
                    /// 多貨幣時顯示貨幣符號和支出率
                    /// Show currency code and spend ratio when multi-currency
                    if summary.isMultiCurrency {
                        HStack {
                            Text(cur.currency)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if cur.income > 0 {
                                Text(String(format: "%.0f%%", cur.spendRatio * 100) + " 支出率")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        /// 單一貨幣時只顯示支出率
                        /// Single currency: only show spend ratio
                        HStack {
                            Spacer()
                            if cur.income > 0 {
                                Text(String(format: "%.0f%%", cur.spendRatio * 100) + " 支出率")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    /// 柱狀圖部分 (Bar chart part) ──────────────────────────
                    /// GeometryReader 提供父視圖的大小信息
                    /// GeometryReader provides parent view size information
                    /// geo.size.width = 可用寬度（以點為單位）
                    /// geo.size.width = available width (in points)
                    /// 柱子寬度 = 可用寬度 × 支出率（0-1）
                    /// Bar width = available width × spend ratio (0-1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            /// 背景柱：淺綠色（顯示 100% 容量）
                            /// Background bar: light green (shows 100% capacity)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green.opacity(0.2))
                                .frame(height: 8)

                            /// 前景柱：實際支出率（顏色根據比例改變）
                            /// Foreground bar: actual spend ratio (color changes with ratio)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    /// 三元運算符進行條件著色
                                    /// Ternary operator for conditional coloring
                                    cur.spendRatio > 0.8 ? Color.red
                                        : cur.spendRatio > 0.5 ? Color.orange
                                        : Color.green
                                )
                                .frame(
                                    /// 寬度 = 可用寬度 × 支出率，最小 0（無負寬度）
                                    /// Width = available width × spend ratio, min 0 (no negative)
                                    width: max(0, geo.size.width * CGFloat(cur.spendRatio)),
                                    height: 8
                                )
                                /// spring 動畫使柱子平滑增長
                                /// spring animation makes bar grow smoothly
                                /// duration: 0.5 = 500 毫秒內完成
                                /// duration: 0.5 = complete within 500ms
                                .animation(.spring(duration: 0.5), value: cur.spendRatio)
                        }
                    }
                    .frame(height: 8)

                    /// 底部：收入和支出標籤
                    /// Bottom: income and expense labels
                    HStack {
                        /// 收入標籤（綠色）
                        /// Income label (green)
                        Label(cur.incomeText, systemImage: "arrow.down.circle.fill")
                            .font(.caption.monospacedDigit()) /// 等寬數字字體
                            .foregroundStyle(.green)
                        Spacer()
                        /// 支出標籤（紅色）
                        /// Expense label (red)
                        Label(cur.expenseText, systemImage: "arrow.up.circle.fill")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
