// TransactionDetailView.swift
// co-money

import SwiftUI

/// TransactionDetailView: 交易詳情頁面
/// Displays full transaction details with edit and delete capabilities
///
/// 核心概念：
/// - @State: 本地狀態控制編輯/刪除模態
/// - sheet(): 編輯模態呈現
/// - confirmationDialog(): 刪除確認對話框
/// - NavigationLink: 返回按鈕自動管理
/// - async/await: 非同步操作
/// - dismiss: 關閉當前視圖
struct TransactionDetailView: View {
    // MARK: - Parameters (外部傳入)
    /// 要顯示的交易對象
    let transaction: Transaction

    // MARK: - Environment Injection (依賴注入)
    @Environment(TransactionViewModel.self) private var vm
    @Environment(AccountViewModel.self)     private var accountVM
    @Environment(ProfileViewModel.self)     private var profileVM

    // Environment 變數：允許此視圖自行關閉
    // 用於刪除後返回列表
    @Environment(\.dismiss)                private var dismiss

    private var currentTransaction: Transaction {
        vm.transaction(matching: transaction.id) ?? transaction
    }

    // MARK: - State: Modal & Dialog Control (模態狀態)
    // 編輯模態是否顯示
    @State private var showEdit          = false

    // 刪除確認對話框是否顯示
    @State private var showDeleteConfirm = false

    var body: some View {
        let transaction = currentTransaction

        // List: 以列表形式展示詳情（提供自動分組、間距管理）
        // Using List instead of VStack provides native iOS appearance
        List {
            // MARK: - 上方：金額展示區 (Amount Header Section)

            Section {
                VStack(spacing: 10) {
                    // 判斷交易類型
                    let isIncome = transaction.transactionType == .income

                    // 交易類型圖標：圓形背景 + 圖標
                    // 顏色編碼：收入綠色，支出紅色
                    ZStack {
                        Circle()
                            .fill((isIncome ? Color.green : Color.red).opacity(0.12))
                            .frame(width: 64, height: 64)
                        Image(systemName: transaction.transactionType.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(isIncome ? .green : .red)
                    }

                    // 金額顯示：+/- 前綴 + 數字 + 幣種
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        // +/- 前綴
                        Text(isIncome ? "+" : "-")
                            .font(.title2.bold())
                            .foregroundStyle(isIncome ? .green : .red)

                        // 金額數字
                        Text(AmountFormatter.format(transaction.amount))
                            .font(.largeTitle.bold().monospacedDigit())

                        // 幣種代碼
                        if let cur = transaction.currency, !cur.isEmpty {
                            Text(cur)
                                .font(.title3.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 支付人徽章
                    // Label: 圖標 + 文字
                    Label(transaction.payer.username, systemImage: "person.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
                // 區塊容器設置
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // MARK: - 詳情區 (Details Section)

            Section("詳情 Details") {
                // LabeledContent: 標籤-內容對的標準容器
                // 自動處理標籤寬度和對齊
                LabeledContent("說明", value: transaction.description)
                LabeledContent("日期", value: transaction.transactionDate.formatted(date: .long, time: .shortened))

                // 分類：可選欄位，僅當有分類時顯示
                if let cat = transaction.category, !cat.isEmpty {
                    LabeledContent("分類", value: cat)
                }

                // 備注：可選欄位，僅當有備注時顯示
                if let notes = transaction.notes, !notes.isEmpty {
                    LabeledContent("備注", value: notes)
                }

                // 支付人
                LabeledContent("付款人", value: transaction.payer.username)
            }

            // MARK: - 帳戶區 (Accounts Section)
            // 條件式區塊：僅當交易關聯帳戶時顯示
            if !transaction.accounts.isEmpty {
                Section("關聯帳戶 Accounts") {
                    // ForEach: 遍歷所有關聯帳戶
                    ForEach(transaction.accounts) { acc in
                        Label(acc.name, systemImage: "person.2.fill")
                    }
                }
            }

            // MARK: - 刪除按鈕區 (Delete Section)

            Section {
                // Button with role: .destructive 表示危險操作
                // 自動樣式為紅色文字
                Button(role: .destructive) {
                    showDeleteConfirm = true  // 觸發刪除確認對話框
                } label: {
                    Label("刪除此筆記帳 Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }

        // MARK: - Navigation & Toolbar

        .navigationTitle("交易詳情")
        .navigationBarTitleDisplayMode(.inline)

        // toolbar: 導覽列按鈕
        .toolbar {
            // .primaryAction: 右側主操作按鈕位置
            ToolbarItem(placement: .primaryAction) {
                Button("編輯") { showEdit = true }  // 點擊顯示編輯表單
            }
        }

        // MARK: - 編輯模態 (Sheet: Edit Transaction)

        /// sheet(isPresented:): 呈現模態視圖
        /// - isPresented: $showEdit 控制模態的顯示/隱藏
        /// - 當用戶從模態返回時，自動設置 showEdit = false
        .sheet(isPresented: $showEdit) {
            // 傳遞當前交易到編輯視圖：editingTransaction 非 nil 表示編輯模式
            AddTransactionView(editingTransaction: transaction)
                .environment(vm)
                .environment(accountVM)
                .environment(profileVM)
        }

        // MARK: - 刪除確認對話框 (Confirmation Dialog)

        /// confirmationDialog(): 確認對話框
        /// - 標題：「確定刪除這筆記帳？」
        /// - isPresented: $showDeleteConfirm 控制對話框顯示/隱藏
        /// - titleVisibility: .visible 顯示對話框標題
        .confirmationDialog(
            "確定刪除這筆記帳？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            // 對話框按鈕

            // 刪除按鈕（紅色危險操作）
            Button("刪除", role: .destructive) {
                Task {
                    // 非同步執行刪除操作
                    await vm.deleteTransaction(id: transaction.id)
                    // 刪除完成後關閉當前視圖，返回列表
                    dismiss()
                }
            }

            // 取消按鈕（灰色，關閉對話框）
            Button("取消", role: .cancel) {}
        }
    }
}
