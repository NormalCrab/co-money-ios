// AddTransactionView.swift
// co-money

import SwiftUI

/// AddTransactionView: 新增或編輯單筆交易的表單視圖
/// A Form-based view for creating or editing a single transaction with
/// multi-step data flow: form inputs → state variables → view model → backend
///
/// 核心概念：
/// - @State: 本地可變狀態（存在此視圖生命週期內）
/// - @Binding: 雙向資料流（當父視圖傳遞 $state 時）
/// - @Environment: 從環境注入 ViewModels（依賴注入模式）
/// - Form / Section: 結構化表單 UI 佈局
/// - NavigationStack: iOS 16+ 導航堆疊
struct AddTransactionView: View {
    // MARK: - Environment Injection (依賴注入)
    // @Environment 從父視圖的環境中取得共享 ViewModels
    // Allows this view to access shared data without prop drilling
    @Environment(TransactionViewModel.self) private var vm
    @Environment(AccountViewModel.self)     private var accountVM
    @Environment(ProfileViewModel.self)     private var profileVM

    // 環境變數：dismiss 閉包允許此視圖自行關閉
    // Environment variable that provides a closure to dismiss this view
    @Environment(\.dismiss)                 private var dismiss

    // MARK: - Parameters (外部傳入)

    /// Pass a transaction to enter edit mode
    /// 編輯模式：非 nil 表示編輯現有交易，nil 表示新增交易
    var editingTransaction: Transaction? = nil

    /// Override for pre-filled accounts. nil = use profile default; [] = personal (no accounts).
    /// 帳戶預設值：可覆蓋。nil 使用用戶設定的預設帳戶
    var defaultAccountIds: [String]? = nil

    // MARK: - State Variables (本地可變狀態)
    // @State 聲明本地可變狀態，當狀態改變時視圖自動重新渲染
    // When @State changes, SwiftUI automatically triggers body recomputation
    @State private var description     = ""
    @State private var amount          = ""
    @State private var currency        = ""
    @State private var transactionType = TransactionType.expense
    @State private var date            = Date()
    @State private var categoryName    = ""
    @State private var notes           = ""
    @State private var selectedAccIds: [String] = []
    @State private var isLoading       = false
    @State private var didPrefill      = false
    @State private var errorMessage:   String?

    // Common currencies for quick selection
    // 常用幣種列表（提供給 Picker 選項）
    private let commonCurrencies = ["TWD", "USD", "EUR", "JPY", "CNY", "HKD", "KRW", "GBP", "SGD", "AUD"]

    // MARK: - Computed Properties (計算屬性)

    /// 判斷是否在編輯模式
    /// Determines if we're editing an existing transaction or creating new
    private var isEditing: Bool { editingTransaction != nil }

    /// 保存按鈕是否可用
    /// Enable save button only if required fields are filled and not loading
    private var canSave: Bool   { !description.isEmpty && !amount.isEmpty && !isLoading }

    /// Categories from profileVM (authoritative) with txVM.categories as fallback
    /// 獲取分類列表：優先使用 profileVM 的分類，若無則使用 txVM 的備用分類
    /// This provides a flexible fallback mechanism for data sources
    private var availableCategories: [Category] {
        var seen = Set<String>()
        var merged: [Category] = []

        for cat in profileVM.categories + vm.categories {
            let key = cat.id.isEmpty ? cat.name.lowercased() : cat.id
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(cat)
        }

        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        // NavigationStack: iOS 16+ 導航容器（支持返回按鈕自動管理）
        // Navigation container that provides back button and swipe-to-pop gestures
        NavigationStack {
            // Form: 結構化表單容器，自動處理鍵盤間距和佈局
            // Form organizes input fields with automatic spacing and keyboard handling
            Form {
                // MARK: - 基本資訊 Section (Basic Information)
                Section("基本資訊") {
                    // TextField: 單行文本輸入，使用 $description 建立雙向綁定
                    // $ prefix creates a Binding: changes update @State automatically
                    TextField("說明 Description", text: $description)

                    HStack {
                        Text("金額 Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)  // 顯示數字鍵盤
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }

                    // Currency picker: 選擇幣種
                    // Picker: Dropdown selector bound to @State currency variable
                    // ForEach generates picker items from commonCurrencies array
                    Picker("幣種 Currency", selection: $currency) {
                        ForEach(commonCurrencies, id: \.self) { cur in
                            Text(cur).tag(cur)  // tag() 設置 Picker 的選中值
                        }
                    }

                    // Type picker: 選擇交易類型（收入/支出）
                    // Segmented picker: displays as horizontal segment buttons
                    Picker("類型 Type", selection: $transactionType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Label(type.localizedName, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    // DatePicker: 日期和時間選擇器
                    // DatePicker bound to @State date variable
                    DatePicker("日期 Date", selection: $date,
                               displayedComponents: [.date, .hourAndMinute])
                }

                // MARK: - 分類 Section (Category)
                // Category — presets are used as quick picks, while free text is allowed.
                // 分類區塊：預設分類作為快速選取，也允許自由輸入。
                Section("分類 Category") {
                    TextField("分類名稱 Category", text: $categoryName)

                    if !availableCategories.isEmpty {
                        Picker("快速選取", selection: $categoryName) {
                            Text("無 None").tag("")
                            ForEach(availableCategories) { cat in
                                HStack {
                                    if let icon = cat.icon, !icon.isEmpty { Text(icon) }
                                    Text(cat.name)
                                }.tag(cat.name)
                            }
                        }
                    }
                }

                // MARK: - 帳戶 Section (Accounts)
                // Accounts section: conditionally shown only if accounts exist
                // 帳戶區塊：僅在帳戶存在時顯示（使用條件式區塊）
                if !accountVM.accounts.isEmpty {
                    Section("關聯帳戶 Accounts") {
                        // ForEach 遍歷每個帳戶，生成 Toggle 選項
                        ForEach(accountVM.accounts) { acc in
                            // Toggle with custom Binding: 手動創建雙向綁定邏輯
                            // 這是處理複雜狀態的高級模式
                            Toggle(acc.name, isOn: Binding(
                                // get: 取值邏輯 - 檢查此帳戶 ID 是否在 selectedAccIds 中
                                get:  { selectedAccIds.contains(acc.id) },
                                // set: 賦值邏輯 - 當 Toggle 狀態改變時更新 selectedAccIds 陣列
                                set:  { on in
                                    if on {
                                        // Toggle 開啟：新增帳戶 ID 到陣列
                                        selectedAccIds.append(acc.id)
                                    }
                                    else  {
                                        // Toggle 關閉：從陣列移除帳戶 ID
                                        selectedAccIds.removeAll { $0 == acc.id }
                                    }
                                }
                            ))
                        }
                    }
                }

                // MARK: - 備注 Section (Notes)
                Section("備注 Notes") {
                    // TextField 支持多行輸入（axis: .vertical）
                    // Multi-line text input with line limit range
                    TextField("選填 Optional", text: $notes, axis: .vertical)
                        .lineLimit(3...6)  // 最少 3 行，最多 6 行
                }

                // MARK: - 錯誤信息 Section (Error Display)
                // 錯誤區塊：僅當 errorMessage 非 nil 時顯示
                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }

            // MARK: - Navigation & Toolbar

            .navigationTitle(isEditing ? "編輯記帳 Edit" : "新增記帳 Add")
            .navigationBarTitleDisplayMode(.inline)

            // toolbar: 定義導覽列上的按鈕
            // toolbar placement 指定按鈕位置
            .toolbar {
                // 左側：取消按鈕
                // .cancellationAction: standard iOS placement for cancel/dismiss
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                // 右側：保存/更新按鈕
                // .confirmationAction: standard iOS placement for confirm/save
                ToolbarItem(placement: .confirmationAction) {
                    // 根據 isLoading 狀態顯示 ProgressView 或 Button
                    // Conditional rendering based on loading state
                    if isLoading {
                        ProgressView()  // 載入中顯示轉圈動畫
                    } else {
                        Button(isEditing ? "更新" : "儲存") {
                            // Task: 非同步執行 save() 函數
                            // Task 執行 async 函數，適合 async/await 模式
                            Task { await save() }
                        }
                        .disabled(!canSave)  // 當 canSave 為 false 時禁用按鈕
                    }
                }
            }

            // onAppear: 視圖出現時的生命週期回調
            // View lifecycle hook: called when view appears on screen
            // 用於初始化狀態或執行載入邏輯
            .onAppear { prefillIfNeeded() }
            .task { await loadCategoriesIfNeeded() }
        }
    }

    // MARK: - Pre-fill Method (預填數據)

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        prefill()
        didPrefill = true
    }

    private func loadCategoriesIfNeeded() async {
        guard availableCategories.isEmpty else { return }
        await profileVM.loadProfile()
        syncCategorySelectionFromEditingTransaction()
    }

    /// 根據 editingTransaction 預填表單，或使用預設值
    /// Populates form fields when editing an existing transaction or on initial load
    ///
    /// 邏輯流程：
    /// 1. 若為編輯模式：從 editingTransaction 複製所有欄位值
    /// 2. 若為新增模式：使用用戶預設值或傳入的預設帳戶
    private func prefill() {
        if let tx = editingTransaction {
            // 編輯模式：讀取現有交易的所有欄位
            description     = tx.description
            amount          = tx.amount
            currency        = tx.currency ?? profileVM.profile?.defaultCurrency ?? commonCurrencies[0]
            transactionType = tx.transactionType
            date            = tx.transactionDate
            notes           = tx.notes ?? ""
            selectedAccIds  = tx.accounts.map { $0.id }  // 提取帳戶 ID 陣列

            syncCategorySelectionFromEditingTransaction()
        } else {
            // 新增模式：使用預設幣種和帳戶
            currency       = profileVM.profile?.defaultCurrency ?? commonCurrencies[0]
            if let overrideIds = defaultAccountIds {
                // 若傳入了預設帳戶 ID，使用它們
                selectedAccIds = overrideIds
            } else {
                // 否則使用用戶設定中的預設共享帳戶
                selectedAccIds = profileVM.profile?.defaultSharedAccounts ?? []
            }
        }
    }

    private func syncCategorySelectionFromEditingTransaction() {
        guard let tx = editingTransaction else { return }
        categoryName = tx.category ?? ""
    }

    // MARK: - Save Method (保存邏輯)

    /// 保存或更新交易
    /// Saves the transaction to backend via ViewModel
    ///
    /// 非同步流程：
    /// 1. 設置 isLoading = true（顯示進度指示器）
    /// 2. 根據編輯狀態調用 updateTransaction 或 createTransaction
    /// 3. 成功後調用 dismiss() 關閉視圖
    /// 4. 失敗時設置 errorMessage（由 UI 自動顯示）
    /// 5. 最後設置 isLoading = false（隱藏進度指示器）
    private func save() async {
        isLoading    = true
        errorMessage = nil
        let cur = currency.trimmingCharacters(in: .whitespaces)
        do {
            if let tx = editingTransaction {
                // 編輯模式：呼叫更新 API
                try await vm.updateTransaction(
                    id:          tx.id,
                    description: description,
                    amount:      amount,
                    currency:    cur.isEmpty ? nil : cur,
                    type:        transactionType,
                    date:        date,
                    category:    categoryName,
                    notes:       notes,
                    accountIds:  selectedAccIds
                )
            } else {
                // 新增模式：呼叫建立 API
                try await vm.createTransaction(
                    description: description,
                    amount:      amount,
                    currency:    cur.isEmpty ? nil : cur,
                    type:        transactionType,
                    date:        date,
                    category:    categoryName,
                    notes:       notes,
                    accountIds:  selectedAccIds
                )
            }
            // 成功後關閉此視圖
            dismiss()
        } catch {
            // 異常時設置錯誤信息（由 Section 顯示）
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
