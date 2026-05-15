// ParsedTransactionPreviewView.swift
// co-money
//
// Shows AI-parsed transactions for user review/edit before saving.
// Flow: Voice/Receipt → text → backend parse → THIS VIEW → user edits → create transactions
//
// 核心流程：
// 1. 後端 AI 解析語音/收據，產生 Transaction 物件列表
// 2. 此視圖讀取解析結果，轉換為可編輯的 DraftTransaction
// 3. 用戶可展開每筆交易進行編輯
// 4. 點擊「全部儲存」時，將所有草稿批量保存到後端

import SwiftUI

// MARK: - Draft Transaction Model (草稿交易模型)

/// DraftTransaction: 可編輯的交易草稿（尚未保存）
/// Mutable intermediate model that sits between parsed AI results and saved transactions
///
/// 設計目的：
/// - Transaction 是後端返回的只讀模型，無法直接編輯
/// - DraftTransaction 是本地可編輯副本，支持用戶修改
/// - 用戶點擊「儲存」時，DraftTransaction 才提交到後端轉為 Transaction
///
/// 雙向轉換：
/// - from(): Transaction → DraftTransaction (解析結果轉草稿)
/// - 保存時：DraftTransaction → API request (草稿轉提交)
struct DraftTransaction: Identifiable {
    // Identifiable 協議：提供唯一識別符，用於 List ForEach 追蹤
    let id = UUID()

    // 後端 parse 回傳的原始 Transaction ID。
    // 若後端在 parse 時就將 transaction 存入 DB，此 ID 為真實的資料庫 ID，
    // 儲存時改用 PATCH（更新），取消時用 DELETE 刪除，避免重複寫入。
    // If the backend saved the transaction during parse, this is a real DB ID.
    // We'll UPDATE on save and DELETE on cancel to prevent duplicate writes.
    let originalId: String

    // MARK: - 基本欄位
    var description: String
    var amount: String
    var currency: String
    var transactionType: TransactionType
    var transactionDate: Date

    // MARK: - 分類欄位：雙重存儲模式
    /// 後端解析結果中的分類名稱（顯示用）
    /// 保持原始的後端返回值，用於 UI 顯示
    var categoryName: String?

    /// 本地分類 ID（提交用）
    /// 由本地分類列表解析得出，對應 Category.id
    /// 用於提交時指定分類
    var categoryId: String?

    // MARK: - 其他欄位
    var notes: String?
    var accountIds: [String]  // 支持多個帳戶

    /// 工廠方法：從後端返回的 Transaction 構建 DraftTransaction
    /// Factory method: converts parsed Transaction to editable DraftTransaction
    ///
    /// 轉換邏輯：
    /// 1. 直接複製基本欄位
    /// 2. 使用預設幣種和帳戶（若後端未返回）
    /// 3. 通過名稱匹配本地分類列表，解析出 categoryId
    ///
    /// 參數：
    /// - tx: 後端解析的交易
    /// - defaultCurrency: 預設幣種（來自用戶設定）
    /// - defaultAccountIds: 預設帳戶（來自用戶設定）
    /// - categories: 本地分類列表（用於名稱→ID 匹配）
    static func from(_ tx: Transaction, defaultCurrency: String, defaultAccountIds: [String], categories: [Category]) -> DraftTransaction {
        // 解析分類：通過名稱匹配本地分類，取得 ID
        // 後端返回的是分類名稱，需要匹配本地 ID
        let catId = tx.category.flatMap { name in
            categories.first { $0.name == name }?.id
        }

        return DraftTransaction(
            originalId:      tx.id,        // 保留後端回傳的原始 ID
            description:     tx.description,
            amount:          tx.amount,
            currency:        tx.currency ?? defaultCurrency,
            transactionType: tx.transactionType,
            transactionDate: tx.transactionDate,
            categoryName:    tx.category,  // 保留原始名稱
            categoryId:      catId,        // 解析出的本地 ID
            notes:           tx.notes,
            accountIds:      defaultAccountIds  // 使用預設帳戶
        )
    }
}

// MARK: - Preview View

/// ParsedTransactionPreviewView: AI 解析結果預覽和編輯視圖
/// Main preview screen for reviewed and edited AI-parsed transactions
///
/// 核心功能：
/// 1. 展示 AI 解析的交易列表
/// 2. 支持點擊展開/收起各筆交易
/// 3. 支持編輯所有欄位
/// 4. 支持刪除交易
/// 5. 批量儲存所有交易
///
/// 狀態流：
/// parsedTransactions (read-only) → buildDrafts() → @State drafts (mutable) → saveAll()
struct ParsedTransactionPreviewView: View {
    // MARK: - Environment Injection (依賴注入)
    @Environment(TransactionViewModel.self) private var txVM
    @Environment(AccountViewModel.self)     private var accountVM
    @Environment(ProfileViewModel.self)     private var profileVM
    @Environment(\.dismiss)                 private var dismiss

    // MARK: - Parameters (外部傳入的只讀數據)

    /// 後端 AI 解析的交易列表（來自語音/收據識別）
    /// Array of parsed transactions from backend AI (read-only source)
    /// 這個參數是只讀的，不會被修改
    let parsedTransactions: [Transaction]

    // MARK: - State: Mutable Local Copies (本地可編輯副本)

    /// 可編輯的交易草稿列表
    /// Local mutable copies derived from parsedTransactions
    /// @State 使得此視圖可以追蹤草稿的所有編輯
    @State private var drafts: [DraftTransaction] = []

    /// 是否正在保存中
    @State private var isSaving    = false

    /// 保存時的錯誤信息
    @State private var errorMessage: String?

    /// 當前展開的草稿 UUID（用於控制展開/收起狀態）
    /// UUID of the currently expanded draft for editing
    /// nil 表示所有草稿都收起
    @State private var editingDraftId: UUID?

    // Common currencies for quick selection
    private let commonCurrencies = ["TWD", "USD", "EUR", "JPY", "CNY", "HKD", "KRW", "GBP", "SGD", "AUD"]

    var body: some View {
        NavigationStack {
            // Group: 用於條件式顯示多個視圖，無視覺層級
            // Group allows conditional logic without adding UI elements
            Group {
                // 根據是否有交易顯示不同內容
                if drafts.isEmpty {
                    // 無數據狀態：顯示空狀態提示
                    ContentUnavailableView(
                        "無法解析",
                        systemImage: "questionmark.circle",
                        description: Text("未能從內容中辨識出交易記錄")
                    )
                } else {
                    // 有數據：顯示可編輯的交易列表
                    List {
                        // Section: 組織列表內容
                        Section {
                            // ForEach($drafts): 使用 $ 前綴建立綁定
                            // $ 綁定允許 DraftTransactionRow 直接修改 draft 的欄位
                            ForEach($drafts) { $draft in
                                DraftTransactionRow(
                                    draft: $draft,  // 傳遞綁定，允許直接編輯
                                    isExpanded: editingDraftId == draft.id,
                                    categories: availableCategories,
                                    accounts: accountVM.accounts,
                                    commonCurrencies: commonCurrencies,
                                    // onToggle: 點擊行時切換展開/收起
                                    onToggle: {
                                        // withAnimation: 動畫展開/收起效果
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            // 如果已展開則收起，否則展開
                                            editingDraftId = editingDraftId == draft.id ? nil : draft.id
                                        }
                                    }
                                )
                            }
                            // onDelete: List 內建的刪除手勢
                            // 向左滑動時顯示刪除選項
                            .onDelete { indices in
                                drafts.remove(atOffsets: indices)
                            }
                        } header: {
                            Text("共 \(drafts.count) 筆交易")
                        } footer: {
                            Text("點擊項目可展開編輯，左滑可刪除")
                                .font(.caption)
                        }

                        // 錯誤信息區塊
                        if let err = errorMessage {
                            Section {
                                Text(err).foregroundStyle(.red).font(.caption)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }

            // MARK: - Navigation & Toolbar

            .navigationTitle("確認交易")
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                // 左側：取消按鈕
                // On cancel: dismiss immediately, then silently delete any transactions
                // that the backend may have auto-saved during the parse step.
                // 取消時：立即關閉，然後在背景靜默刪除後端 parse 時自動存入的交易。
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        let ids = drafts.map { $0.originalId }
                        dismiss()
                        Task { await txVM.deleteParsed(ids: ids) }
                    }
                }

                // 右側：儲存按鈕
                ToolbarItem(placement: .confirmationAction) {
                    // 根據 isSaving 狀態顯示不同內容
                    if isSaving {
                        ProgressView()  // 保存中：顯示進度指示器
                    } else {
                        Button("全部儲存") {
                            Task { await saveAll() }
                        }
                        .disabled(drafts.isEmpty)  // 無交易時禁用按鈕
                        .bold()
                    }
                }
            }

            // onAppear: 視圖出現時初始化草稿
            // View lifecycle: build drafts when view appears
            .onAppear { buildDrafts() }
        }
    }

    // MARK: - Helpers

    /// 獲取可用分類列表
    /// Returns available categories with fallback logic
    private var availableCategories: [Category] {
        profileVM.categories.isEmpty ? txVM.categories : profileVM.categories
    }

    /// 構建草稿列表：從 parsedTransactions 轉換為可編輯的 DraftTransaction
    /// Initializes draft list from parsed transactions
    ///
    /// 邏輯：
    /// 1. 獲取用戶預設幣種和帳戶
    /// 2. 使用 DraftTransaction.from() 轉換每筆交易
    /// 3. 賦值給 @State drafts
    private func buildDrafts() {
        let defaultCurrency = profileVM.profile?.defaultCurrency ?? "TWD"
        let defaultAccounts = profileVM.profile?.defaultSharedAccounts ?? []
        let cats = availableCategories
        drafts = parsedTransactions.map {
            DraftTransaction.from($0, defaultCurrency: defaultCurrency, defaultAccountIds: defaultAccounts, categories: cats)
        }
    }

    /// 批量保存所有草稿
    /// Saves all draft transactions to backend
    ///
    /// 非同步流程：
    /// 1. 設置 isSaving = true（禁用保存按鈕，顯示進度）
    /// 2. 呼叫 VM 的 createBatch() 方法
    /// 3. 成功時調用 dismiss() 返回前一頁
    /// 4. 失敗時設置 errorMessage（由 UI 顯示）
    /// 5. 最後設置 isSaving = false（恢復按鈕）
    private func saveAll() async {
        isSaving     = true
        errorMessage = nil
        do {
            // Use updateBatch instead of createBatch.
            // updateBatch will PATCH existing transactions (if the backend already saved them
            // during parse), or fall back to POST if they don't exist yet.
            // 改用 updateBatch 取代 createBatch。
            // updateBatch 優先 PATCH 現有記錄（後端 parse 時已存），
            // 若不存在則退而 POST 建立，避免重複寫入。
            try await txVM.updateBatch(drafts)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Draft Transaction Row Component (草稿交易行元件)

/// DraftTransactionRow: 單行可展開/收起的交易編輯器
/// Expandable transaction row with edit controls
///
/// 功能：
/// 1. 摺疊狀態：顯示交易摘要（圖標、描述、金額）
/// 2. 展開狀態：展示所有可編輯欄位
/// 3. 使用 @Binding 直接修改父視圖的 draft 物件
///
/// 綁定流程：
/// - DraftTransactionRow 接收 @Binding $draft
/// - 所有 TextField、Picker 等控件直接綁定到 $draft 的欄位
/// - 修改自動同步回父視圖的 @State drafts
private struct DraftTransactionRow: View {
    // MARK: - Parameters

    /// @Binding: 雙向綁定到父視圖的 DraftTransaction
    /// Binding allows this view to modify the parent's draft directly
    /// 父視圖傳遞 $draft（使用 $ 前綴建立綁定）
    @Binding var draft: DraftTransaction

    // 是否展開編輯區域
    let isExpanded: Bool

    // UI 數據
    let categories: [Category]
    let accounts: [SharedAccount]
    let commonCurrencies: [String]

    // 回調：點擊行時執行
    let onToggle: () -> Void

    // MARK: - Computed Properties (計算屬性)
    private var isIncome: Bool { draft.transactionType == .income }

    var body: some View {
        // VStack: 垂直排列摘要行 + 展開區域
        // alignment: .leading 左對齐
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - 摘要行（始終可見，可點擊）

            /// Button(action: onToggle): 可點擊的行
            /// Entire row is tappable to expand/collapse
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // MARK: - 左側：交易類型圖標

                    ZStack {
                        Circle()
                            .fill(isIncome ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: draft.transactionType.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isIncome ? .green : .red)
                    }

                    // MARK: - 中間：交易描述和元信息

                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.description)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            // 分類徽章
                            if let cat = draft.categoryName, !cat.isEmpty {
                                Text(cat)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }

                            // 日期
                            Text(draft.transactionDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // MARK: - 右側：金額和幣種

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(isIncome ? "+" : "-")\(AmountFormatter.format(draft.amount))")
                            .font(.body.monospacedDigit().bold())
                            .foregroundStyle(isIncome ? .green : .primary)
                        Text(draft.currency)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }

                    // MARK: - 右邊界：展開/收起指示圖標

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)  // 移除 Button 預設樣式（使用行的自然色彩）

            // MARK: - 展開區域（僅當 isExpanded 時顯示）

            /// if isExpanded: 條件式渲染展開的編輯區域
            /// Expanded form shows when user taps the row
            if isExpanded {
                Divider().padding(.vertical, 8)

                // VStack: 編輯表單欄位
                VStack(spacing: 12) {
                    // MARK: - 說明輸入

                    HStack {
                        Text("說明")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        // 直接綁定到 $draft.description
                        // TextField 會修改 draft.description，自動同步回父視圖
                        TextField("說明", text: $draft.description)
                            .font(.subheadline)
                    }

                    // MARK: - 金額輸入

                    HStack {
                        Text("金額")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        TextField("0.00", text: $draft.amount)
                            .keyboardType(.decimalPad)
                            .font(.subheadline)
                    }

                    // MARK: - 幣種選擇

                    HStack {
                        Text("幣種")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        // Picker 直接綁定到 $draft.currency
                        Picker("", selection: $draft.currency) {
                            ForEach(commonCurrencies, id: \.self) { cur in
                                Text(cur).tag(cur)
                            }
                        }
                        .labelsHidden()  // 隱藏 Picker 標籤
                        .pickerStyle(.menu)  // 菜單式 Picker
                    }

                    // MARK: - 交易類型選擇

                    Picker("類型", selection: $draft.transactionType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    // MARK: - 日期選擇

                    DatePicker("日期", selection: $draft.transactionDate, displayedComponents: [.date])
                        .font(.subheadline)

                    // MARK: - 分類選擇

                    if !categories.isEmpty {
                        HStack {
                            Text("分類")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            // Picker 直接綁定到 $draft.categoryId
                            Picker("", selection: $draft.categoryId) {
                                Text("無").tag(String?.none)
                                ForEach(categories) { cat in
                                    HStack {
                                        if let icon = cat.icon, !icon.isEmpty { Text(icon) }
                                        Text(cat.name)
                                    }.tag(Optional(cat.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)

                            // onChange: 當分類 ID 改變時，同步更新分類名稱
                            // Sync categoryName when categoryId changes
                            .onChange(of: draft.categoryId) { _, newId in
                                draft.categoryName = categories.first { $0.id == newId }?.name
                            }
                        }
                    }

                    // MARK: - 帳戶選擇（多選）

                    if !accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("帳戶")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            // ForEach 遍歷帳戶列表
                            ForEach(accounts) { acc in
                                // Toggle with custom Binding
                                // 處理複雜的陣列相關邏輯：檢查 ID 是否在陣列中
                                Toggle(acc.name, isOn: Binding(
                                    get: { draft.accountIds.contains(acc.id) },
                                    set: { on in
                                        if on { draft.accountIds.append(acc.id) }
                                        else  { draft.accountIds.removeAll { $0 == acc.id } }
                                    }
                                ))
                                .font(.subheadline)
                            }
                        }
                    }

                    // MARK: - 備注輸入

                    HStack {
                        Text("備注")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        // 備注是可選欄位 (String?)，需要手動管理 nil
                        // Binding() 轉換 String? ↔ String
                        TextField("選填", text: Binding(
                            get: { draft.notes ?? "" },  // nil → ""
                            set: { draft.notes = $0.isEmpty ? nil : $0 }  // "" → nil
                        ))
                        .font(.subheadline)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
