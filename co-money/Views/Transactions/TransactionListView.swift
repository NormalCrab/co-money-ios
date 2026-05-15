// TransactionListView.swift
// co-money

import SwiftUI
import UIKit

/// TransactionListView: 交易列表主視圖，展示當月交易記錄
/// Main transaction list view with month navigation, three input methods, and FAB menu
///
/// 核心概念：
/// - ZStack: 疊層布局（層級化組織）
/// - List: 滾動列表容器，支持刪除、重新排序
/// - sheet(): 模態彈窗（輕量級表單展示）
/// - NavigationLink: 宣告式導航（推送到詳情頁）
/// - @State showX: 控制彈窗展示
/// - Menu: 浮動按鈕選單（多選項操作）
struct TransactionListView: View {
    // MARK: - Environment Injection (依賴注入)
    @Environment(TransactionViewModel.self) private var vm
    @Environment(AccountViewModel.self)     private var accountVM
    @Environment(ProfileViewModel.self)     private var profileVM

    // MARK: - State: Modal Presentation (模態狀態)
    // 這些 @State 變數控制三個不同的模態視圖何時出現
    // Each @State variable controls presentation of a different input method sheet
    @State private var showManualAdd     = false  // 手動輸入表單
    @State private var showVoiceInput    = false  // 語音輸入視圖
    @State private var showReceiptScan   = false  // 收據掃描視圖

    var body: some View {
        // NavigationStack: iOS 16+ 導航容器
        // Navigation container for handling navigation to detail views
        NavigationStack {
            // ZStack: 疊層布局，將多個視圖堆疊在 Z 軸上
            // alignment: .bottomTrailing 設置浮動按鈕到右下角
            // ZStack enables floating action button overlaid on top of content
            ZStack(alignment: .bottomTrailing) {
                // VStack: 垂直排列主要內容區域
                // spacing: 0 表示元素間無間距（由子元素自行控制）
                VStack(spacing: 0) {
                    // MARK: - 月份導航欄 (Month Navigation Bar)
                    // 可重用元件：顯示當前月份，支持上一月/下一月導航
                    // Reusable component: custom month picker with previous/next buttons
                    MonthNavigationBar(
                        currentMonth: vm.currentMonth,
                        hasPrevious:  vm.hasPreviousMonth && !vm.isChangingMonth,
                        hasNext:      vm.hasNextMonth && !vm.isChangingMonth,
                        onPrevious:   { Task { await vm.loadPreviousMonth() } },
                        onNext:       { Task { await vm.loadNextMonth() } }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))

                    Divider()  // 水平分隔線

                    // MARK: - 內容區域 (Content Area)
                    // 根據不同狀態顯示不同的內容
                    // Conditional rendering based on data loading state
                    if vm.isLoading && vm.transactions.isEmpty {
                        // 載入中：顯示進度指示器
                        Spacer()
                        ProgressView("載入中...")
                        Spacer()
                    } else if vm.transactions.isEmpty {
                        // 無數據：顯示空狀態提示
                        // ContentUnavailableView: iOS 17 新增組件，用於展示空狀態
                        ContentUnavailableView(
                            "本月尚無記帳",
                            systemImage: "tray",
                            description: Text("點擊右下角 + 開始記帳")
                        )
                    } else {
                        // 有數據：顯示列表
                        // List: 自動提供滾動、刪除手勢等功能
                        List {
                            // ForEach: 遍歷交易列表，為每個交易生成一行
                            ForEach(vm.transactions) { tx in
                                // NavigationLink: 宣告式導航
                                // 點擊此行時推送到 TransactionDetailView
                                // Navigation link without explicit button: entire row is tappable
                                NavigationLink {
                                    // destination: 導航目標視圖
                                    TransactionDetailView(transaction: tx)
                                        .environment(vm)
                                        .environment(accountVM)
                                        .environment(profileVM)
                                } label: {
                                    // label: 行的視覺展示
                                    TransactionRowView(transaction: tx)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            // onDelete: List 內建的刪除手勢支持
                            // 向左滑動時顯示刪除按鈕
                            // Swipe-to-delete: indices contains the rows being deleted
                            .onDelete { indices in
                                for i in indices {
                                    Task { await vm.deleteTransaction(id: vm.transactions[i].id) }
                                }
                            }
                        }
                        .listStyle(.plain)  // 移除 List 預設樣式

                        // refreshable: 下拉重新整理手勢支持
                        // Pull-to-refresh: calls vm.loadAll() when user pulls down
                        .refreshable { await vm.loadAll() }
                    }
                }

                // MARK: - 浮動操作按鈕 (Floating Action Button)
                // Menu: 點擊顯示選項選單
                // Menu: iOS 16+ 組件，點擊時展示多個按鈕選項
                Menu {
                    // 三個不同的記帳方式：手動、語音、收據掃描
                    Button { showManualAdd   = true } label: { Label("手動輸入", systemImage: "square.and.pencil") }
                    Button { showVoiceInput  = true } label: { Label("語音輸入", systemImage: "mic.fill") }
                    Button { showReceiptScan = true } label: { Label("收據辨識", systemImage: "doc.text.viewfinder") }
                } label: {
                    // Menu 按鈕外觀：圓形，帶陰影
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor)
                        .clipShape(Circle())  // 裁剪成圓形
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }

            // MARK: - Navigation 設定

            .navigationTitle("co-money")
            .navigationBarTitleDisplayMode(.large)

            // MARK: - 模態視圖：手動輸入 (Sheet: Manual Add)
            // sheet: 呈現模態視圖（從下往上滑出）
            // isPresented: $showManualAdd 建立雙向綁定
            // 當 showManualAdd 改變時，自動顯示/隱藏此 sheet
            .sheet(isPresented: $showManualAdd) {
                AddTransactionView()
                    .environment(vm)
                    .environment(accountVM)
                    .environment(profileVM)
            }

            // MARK: - 模態視圖：語音輸入 (Sheet: Voice Input)
            .sheet(isPresented: $showVoiceInput) {
                VoiceInputView()
                    .environment(vm)
                    .environment(accountVM)
                    .environment(profileVM)
            }

            // MARK: - 模態視圖：收據掃描 (Sheet: Receipt Scan)
            .sheet(isPresented: $showReceiptScan) {
                ReceiptCaptureView()
                    .environment(vm)
                    .environment(accountVM)
                    .environment(profileVM)
            }

            // MARK: - 錯誤警告 (Alert: Error Display)
            // alert: 顯示警告對話框
            // isPresented: .constant(vm.errorMessage != nil) 基於 vm.errorMessage 是否存在
            // constant() 表示固定綁定（單向，不會改變源變數）
            .alert("錯誤", isPresented: .constant(vm.errorMessage != nil)) {
                Button("確定") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }
}

// MARK: - 月份導航欄元件 (Month Navigation Bar Component)

/// MonthNavigationBar: 可重用的月份導航元件
/// Reusable component for displaying and navigating between months
///
/// 設計模式：
/// - 接收當前月份、導航按鈕狀態作為參數
/// - 使用 Closure 回調執行月份變更邏輯
/// - 無需知道月份數據來源，完全由父視圖控制
struct MonthNavigationBar: View {
    // MARK: - Parameters (外部傳入的參數)
    let currentMonth: String?
    let hasPrevious:  Bool
    let hasNext:      Bool

    // MARK: - Closures (回調函數)
    // 點擊前一月/下一月時的回調
    // Closures for parent view to handle navigation
    let onPrevious:   () -> Void
    let onNext:       () -> Void

    private func monthNavigationFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Computed Property (計算屬性)

    /// 格式化顯示月份字符串
    /// Converts "2024-03" format to localized "March 2024" display
    ///
    /// 邏輯：
    /// 1. 解析 "YYYY-MM" 格式字符串
    /// 2. 使用 DateComponents 和 Calendar 轉換為 Date
    /// 3. 使用 DateFormatter 格式化為本地化語言
    private var displayMonth: String {
        guard let m = currentMonth else { return "本月" }
        let parts = m.split(separator: "-")
        if parts.count == 2, let y = Int(parts[0]), let mo = Int(parts[1]) {
            var comps = DateComponents()
            comps.year = y; comps.month = mo
            if let date = Calendar.current.date(from: comps) {
                return date.formatted(.dateTime.year().month(.wide))
            }
        }
        return m
    }

    var body: some View {
        // HStack: 水平排列三個元素（前按鈕、月份、後按鈕）
        HStack {
            // MARK: - 前一月按鈕

            Button {
                monthNavigationFeedback()
                onPrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.bold())
                    // 按鈕狀態：可用時為強調色，禁用時為灰色
                    .foregroundStyle(hasPrevious ? Color.accentColor : Color(.systemGray3))
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(!hasPrevious)  // 無前月時禁用按鈕

            Spacer()

            // MARK: - 月份顯示
            Text(displayMonth)
                .font(.headline)

            Spacer()

            // MARK: - 下一月按鈕

            Button {
                monthNavigationFeedback()
                onNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.bold())
                    // 按鈕狀態：可用時為強調色，禁用時為灰色
                    .foregroundStyle(hasNext ? Color.accentColor : Color(.systemGray3))
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(!hasNext)  // 無後月時禁用按鈕
        }
    }
}

// MARK: - 交易列表行元件 (Transaction Row Component)

/// TransactionRowView: 單行交易記錄展示
/// Displays a single transaction in the list with icon, description, amount
///
/// 視覺層次：
/// - 圖標：顏色編碼（綠色=收入，紅色=支出）
/// - 描述：交易名稱、分類、帳戶、支付人、日期
/// - 金額：數字對齊、貨幣代碼
struct TransactionRowView: View {
    let transaction: Transaction

    // MARK: - Computed Properties (計算屬性)
    private var isIncome: Bool  { transaction.transactionType == .income }
    private var accent: Color   { isIncome ? .green : Color(.systemRed) }

    var body: some View {
        // HStack: 水平排列三個主要區域（圖標、內容、金額）
        HStack(alignment: .center, spacing: 12) {
            // MARK: - 左側：交易類型圖標

            // ZStack: 圖標背景圓形 + 圖標
            // 顏色編碼：收入綠色，支出紅色
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))  // 淡色背景
                    .frame(width: 40, height: 40)
                Image(systemName: transaction.transactionType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)  // 深色圖標
            }

            // MARK: - 中間：交易詳情

            VStack(alignment: .leading, spacing: 4) {
                // 第一行：交易描述
                Text(transaction.description)
                    .font(.body)
                    .lineLimit(1)  // 超長時截斷

                // 第二行：分類、帳戶、支付人、日期
                // 使用 HStack 水平排列多個徽章
                HStack(spacing: 5) {
                    // 分類徽章
                    if let cat = transaction.category, !cat.isEmpty {
                        Text(cat)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())  // 膠囊形狀
                    }

                    // 帳戶徽章
                    // 支持多個帳戶：ForEach 遍歷 transaction.accounts 陣列
                    ForEach(transaction.accounts) { acc in
                        Text(acc.name)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }

                    // 支付人標籤
                    // Label: 圖標 + 文字組合
                    Label(transaction.payer.username, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)

                    // 分隔點
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // 日期
                    Text(transaction.transactionDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // MARK: - 右側：金額和幣種

            VStack(alignment: .trailing, spacing: 2) {
                // 金額：前綴 +/- 表示收入/支出
                // monospacedDigit(): 使用等寬數字字體（對齐數字）
                Text("\(isIncome ? "+" : "-")\(AmountFormatter.format(transaction.amount))")
                    .font(.body.monospacedDigit().bold())
                    .foregroundStyle(isIncome ? .green : .primary)

                // 幣種代碼
                if let currency = transaction.currency, !currency.isEmpty {
                    Text(currency)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
