//
//  ContentView.swift
//  family_account
//
//  Created by Alexander Kang on 2026/7/5.
//

import SwiftUI

struct ContentView: View {
    @State private var store = AppStore()
    @State private var selectedTab: AppTab = .home
    @State private var accountScope: AccountScope = .shared
    @State private var transactionFilter: TransactionFilter = .all
    @State private var showingAddExpense = false
    @State private var showingVoiceCapture = false
    @State private var showingPhotoCapture = false
    @State private var showingFamily = false
    @State private var selectedProject: ProjectDefinition?
    @State private var editingTransaction: TransactionItem?

    private var scopedTransactions: [TransactionItem] {
        switch accountScope {
        case .shared:
            store.sharedTransactions
        case .privateMoney:
            store.privateTransactions
        case .overview:
            (store.sharedTransactions + store.privateTransactions).sorted { $0.date > $1.date }
        }
    }

    private var filteredTransactions: [TransactionItem] {
        switch transactionFilter {
        case .all:
            scopedTransactions
        case .member(let id):
            scopedTransactions.filter { $0.recorderID == id }
        case .ai:
            scopedTransactions.filter(\.isAI)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    store: store,
                    accountScope: $accountScope,
                    transactionFilter: $transactionFilter,
                    transactions: filteredTransactions,
                    onAddExpense: { showingAddExpense = true },
                    onVoiceCapture: { showingVoiceCapture = true },
                    onPhotoCapture: { showingPhotoCapture = true },
                    onSelectBudget: { selectedTab = .budget },
                    onShowFamily: { showingFamily = true },
                    onEditTransaction: { editingTransaction = $0 }
                )
            }
            .tabItem { Label("首頁", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                ProjectsView(store: store, selectedProject: $selectedProject)
            }
            .tabItem { Label("專案", systemImage: "tag.fill") }
            .tag(AppTab.projects)

            NavigationStack {
                BudgetView(store: store)
            }
            .tabItem { Label("預算", systemImage: "speedometer") }
            .tag(AppTab.budget)

            NavigationStack {
                ReportsView(store: store)
            }
            .tabItem { Label("報表", systemImage: "chart.pie.fill") }
            .tag(AppTab.reports)
        }
        .tint(.teal)
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseSheet(store: store) { transaction in
                store.addTransaction(transaction, sourceLabel: "手動新增")
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingVoiceCapture) {
            VoiceCaptureSheet(currentMemberID: store.currentMemberID) { transaction in
                store.addTransaction(transaction, sourceLabel: "AI 語音")
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingPhotoCapture) {
            PhotoCaptureSheet(currentMemberID: store.currentMemberID) { transaction in
                store.addTransaction(transaction, sourceLabel: "收據照片")
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingFamily) {
            FamilyView(store: store)
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(store: store, project: project)
                .presentationDetents([.large])
        }
        .sheet(item: $editingTransaction) { transaction in
            EditTransactionSheet(
                transaction: transaction,
                recorderName: store.member(transaction.recorderID)?.name ?? "未知成員"
            ) { updated in
                store.updateTransaction(updated)
            }
            .presentationDetents([.large])
        }
    }
}

private enum AppTab: Hashable {
    case home
    case projects
    case budget
    case reports
}

/// 明細篩選：全部 / 個別成員 / AI 輸入。成員動態產生，不再寫死。
enum TransactionFilter: Hashable {
    case all
    case member(UUID)
    case ai
}

// MARK: - Home

private struct HomeView: View {
    var store: AppStore
    @Binding var accountScope: AccountScope
    @Binding var transactionFilter: TransactionFilter
    let transactions: [TransactionItem]
    let onAddExpense: () -> Void
    let onVoiceCapture: () -> Void
    let onPhotoCapture: () -> Void
    let onSelectBudget: () -> Void
    let onShowFamily: () -> Void
    let onEditTransaction: (TransactionItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeaderView(memberCount: store.members.count)

                Picker("帳戶", selection: $accountScope) {
                    ForEach(AccountScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                AccountSummaryCard(
                    scope: accountScope,
                    sharedTotal: store.sharedTotalThisMonth,
                    privateTotal: store.privateTotalThisMonth,
                    memberSplit: store.memberSplitThisMonth(),
                    budgetTotal: store.budget.total,
                    onSelectBudget: onSelectBudget
                )

                SyncStatusRow(
                    changes: store.syncQueue,
                    isSyncing: store.isSyncing,
                    lastSyncText: store.lastSyncText,
                    onSync: { store.sync() }
                )

                if !store.pendingFixedExpenses.isEmpty {
                    FixedExpenseSection(
                        expenses: store.pendingFixedExpenses,
                        onConfirm: { store.confirmFixedExpense($0) },
                        onSkip: { store.skipFixedExpense($0) }
                    )
                }

                TransactionListSection(
                    store: store,
                    transactionFilter: $transactionFilter,
                    transactions: transactions,
                    onEdit: onEditTransaction,
                    onDelete: { store.deleteTransaction($0) }
                )
            }
            .padding(16)
            .padding(.bottom, 88)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            InputMethodDock(
                onAddExpense: onAddExpense,
                onVoiceCapture: onVoiceCapture,
                onPhotoCapture: onPhotoCapture
            )
        }
        .navigationTitle("Family Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onShowFamily) {
                    Image(systemName: "person.2.badge.plus")
                }
                .accessibilityLabel("家庭成員與邀請")
            }
        }
    }
}

private struct HeaderView: View {
    let memberCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("家庭記帳")
                .font(.largeTitle.bold())
            Text("\(memberCount) 位成員 · 手動可離線，AI 輸入用 mock API 解析")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InputMethodDock: View {
    let onAddExpense: () -> Void
    let onVoiceCapture: () -> Void
    let onPhotoCapture: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAddExpense) {
                Label("手動", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onVoiceCapture) {
                Label("語音", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onPhotoCapture) {
                Label("拍照", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}

private struct AccountSummaryCard: View {
    let scope: AccountScope
    let sharedTotal: Int
    let privateTotal: Int
    let memberSplit: [(member: Member, total: Int)]
    let budgetTotal: Int
    let onSelectBudget: () -> Void

    private var visibleTotal: Int {
        switch scope {
        case .shared: sharedTotal
        case .privateMoney: privateTotal
        case .overview: sharedTotal + privateTotal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scope.label)
                        .font(.headline)
                    Text(scope == .overview ? "含私房錢，僅本人裝置可見" : "本月支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(currency(visibleTotal))
                    .font(.title.bold())
                    .monospacedDigit()
            }

            if scope == .shared {
                SegmentedBar(entries: memberSplit.map { ($0.member.color.color, $0.total) })
                HStack {
                    ForEach(memberSplit, id: \.member.id) { entry in
                        LegendTotal(name: "\(entry.member.initial) recorded", amount: entry.total, color: entry.member.color.color)
                        if entry.member.id != memberSplit.last?.member.id {
                            Spacer()
                        }
                    }
                }
            } else if scope == .privateMoney {
                Label("Encrypted private ledger · 不計入家庭總帳", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SegmentedBar(entries: [(.blue, sharedTotal), (.purple, privateTotal)])
                    HStack {
                        LegendTotal(name: "Shared", amount: sharedTotal, color: .blue)
                        Spacer()
                        LegendTotal(name: "Private", amount: privateTotal, color: .purple)
                    }
                }
            }

            Button(action: onSelectBudget) {
                HStack {
                    Label("預算 \(currency(budgetTotal))", systemImage: "speedometer")
                    Spacer()
                    Text("›")
                        .font(.title3.bold())
                }
                .font(.headline)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SyncStatusRow: View {
    let changes: [SyncChange]
    let isSyncing: Bool
    let lastSyncText: String
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: changes.isEmpty ? "checkmark.icloud.fill" : "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(changes.isEmpty ? Color.secondary : Color.teal)

            Text(changes.isEmpty ? lastSyncText : "\(changes.count) 筆待同步")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if let latest = changes.first {
                Text("\(latest.kind.label) · \(latest.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onSync) {
                if isSyncing {
                    ProgressView()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderless)
            .disabled(changes.isEmpty || isSyncing)
            .accessibilityLabel("同步待送出的變更")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FixedExpenseSection: View {
    let expenses: [FixedExpense]
    let onConfirm: (FixedExpense) -> Void
    let onSkip: (FixedExpense) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("固定支出確認")
                .font(.headline)

            ForEach(expenses) { expense in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(expense.title, systemImage: expense.category.icon)
                            .font(.headline)
                        Spacer()
                        Text(currency(expense.amount))
                            .font(.headline.monospacedDigit())
                    }
                    HStack {
                        Text(expense.dueText)
                        Text(expense.tag)
                        if expense.repeatSetting.frequency != .none {
                            Text("🔁 \(expense.repeatSetting.label)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Button("確認入帳") {
                            onConfirm(expense)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("這個月跳過") {
                            onSkip(expense)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(14)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct TransactionListSection: View {
    var store: AppStore
    @Binding var transactionFilter: TransactionFilter
    let transactions: [TransactionItem]
    let onEdit: (TransactionItem) -> Void
    let onDelete: (TransactionItem) -> Void

    private var grouped: [(String, [TransactionItem])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "M/d EEEE"
        let groups = Dictionary(grouping: transactions) { formatter.string(from: $0.date) }
        return groups.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.1.first?.date ?? .distantPast > $1.1.first?.date ?? .distantPast }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("明細")
                    .font(.headline)
                Spacer()
                Picker("篩選", selection: $transactionFilter) {
                    Text("全部").tag(TransactionFilter.all)
                    ForEach(store.members) { member in
                        Text(member.initial).tag(TransactionFilter.member(member.id))
                    }
                    Text("AI").tag(TransactionFilter.ai)
                }
                .pickerStyle(.menu)
            }

            if transactions.isEmpty {
                Text("這個範圍還沒有交易")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            ForEach(grouped, id: \.0) { day, items in
                VStack(alignment: .leading, spacing: 8) {
                    Text(day)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(items) { item in
                        TransactionRow(item: item, recorder: store.member(item.recorderID))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    onDelete(item)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }

                                Button {
                                    onEdit(item)
                                } label: {
                                    Label("修改", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
        }
    }
}

private struct TransactionRow: View {
    let item: TransactionItem
    let recorder: Member?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.category.color.opacity(0.18))
                Image(systemName: item.category.icon)
                    .foregroundStyle(item.category.color)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                    RecorderBadge(recorder: recorder)
                    if item.isAI {
                        TagChip(text: "AI", color: .teal)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        TagChip(text: item.category.label, color: item.category.color)
                        TagChip(text: item.account.label, color: item.account == .shared ? .blue : .purple)
                        ForEach(item.tags, id: \.self) { tag in
                            TagChip(text: tag, color: .gray)
                        }
                        if item.repeatSetting.frequency != .none {
                            TagChip(text: item.repeatLabel, color: .mint)
                        }
                    }
                }
            }

            Spacer()

            Text(currency(item.amount))
                .font(.headline.monospacedDigit())
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Add / Edit Sheets

private struct AddExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    var store: AppStore
    let onSave: (TransactionItem) -> Void

    @State private var title = ""
    @State private var amountText = ""
    @State private var category: ExpenseCategory = .food
    @State private var account: AccountKind = .shared
    @State private var tagText = ""
    @State private var repeatSetting: RepeatSetting = .none
    @State private var showingAdvanced = false

    private var amount: Int {
        Int(amountText.filter(\.isNumber)) ?? 0
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0
    }

    /// 選中分類的本月超支金額（> 0 才提示）。
    private var overspend: Int {
        let spent = store.categorySpendingThisMonth[category, default: 0]
        let limit = store.budget.categoryLimits[category, default: 0]
        return limit > 0 ? max(spent - limit, 0) : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("快速記一筆")
                            .font(.title2.bold())
                        Text("記錄者：\(store.currentMember.name) · 手動輸入不用網路，會先存在本機。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        TextField("金額，例如 680", text: $amountText)
                            .keyboardType(.numberPad)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        TextField("買了什麼？例如 晚餐", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    Picker("帳戶", selection: $account) {
                        ForEach(AccountKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("分類")
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
                            ForEach(ExpenseCategory.allCases) { item in
                                CategoryButton(category: item, isSelected: category == item) {
                                    category = item
                                }
                            }
                        }
                    }

                    DisclosureGroup(isExpanded: $showingAdvanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            TagInputField(text: $tagText)

                            RepeatSettingsView(setting: $repeatSetting)

                            if overspend > 0 {
                                Label("\(category.label) 類本月已超支 \(currency(overspend))，但不阻擋入帳。", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.top, 10)
                    } label: {
                        Label("進階設定", systemImage: "slider.horizontal.3")
                            .font(.headline)
                    }
                    .padding(14)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        save()
                    } label: {
                        Label("離線儲存", systemImage: "tray.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSave)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("新增支出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save() {
        onSave(TransactionItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            date: .now,
            category: category,
            account: account,
            recorderID: store.currentMemberID,
            tags: parseTags(tagText),
            repeatSetting: repeatSetting,
            source: .manual
        ))
        dismiss()
    }
}

private struct EditTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let transaction: TransactionItem
    let recorderName: String
    let onSave: (TransactionItem) -> Void

    @State private var title: String
    @State private var amountText: String
    @State private var category: ExpenseCategory
    @State private var account: AccountKind
    @State private var tagText: String
    @State private var repeatSetting: RepeatSetting

    init(transaction: TransactionItem, recorderName: String, onSave: @escaping (TransactionItem) -> Void) {
        self.transaction = transaction
        self.recorderName = recorderName
        self.onSave = onSave
        _title = State(initialValue: transaction.title)
        _amountText = State(initialValue: String(transaction.amount))
        _category = State(initialValue: transaction.category)
        _account = State(initialValue: transaction.account)
        _tagText = State(initialValue: transaction.tags.joined(separator: " "))
        _repeatSetting = State(initialValue: transaction.repeatSetting)
    }

    private var amount: Int {
        Int(amountText.filter(\.isNumber)) ?? 0
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資料") {
                    TextField("項目", text: $title)
                    TextField("金額", text: $amountText)
                        .keyboardType(.numberPad)
                    Picker("帳戶", selection: $account) {
                        ForEach(AccountKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    // 記錄者不可修改：永遠是當初記帳的人（對齊 spec 的 recordedByUserId）。
                    LabeledContent("記錄者", value: recorderName)
                }

                Section("分類") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
                        ForEach(ExpenseCategory.allCases) { item in
                            CategoryButton(category: item, isSelected: category == item) {
                                category = item
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("專案與重複") {
                    TagInputField(text: $tagText)
                    RepeatSettingsView(setting: $repeatSetting)
                    Text("修改後會先存在本機，並加入待同步佇列。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("修改明細")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        var updated = transaction
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.amount = amount
        updated.category = category
        updated.account = account
        updated.tags = parseTags(tagText)
        updated.repeatSetting = repeatSetting
        onSave(updated)
        dismiss()
    }
}

/// 多 tag 輸入：以空格或逗號分隔，自動補 # 前綴。
private struct TagInputField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Tag，例如 #2026日本旅遊 #日常", text: $text)
                .textFieldStyle(.roundedBorder)
            Text("可輸入多個，用空格分隔；沒加 # 會自動補上。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 把輸入字串解析成 tag 陣列。
private func parseTags(_ text: String) -> [String] {
    text.split(whereSeparator: { $0.isWhitespace || $0 == "," })
        .map { raw in
            let tag = String(raw)
            return tag.hasPrefix("#") ? tag : "#\(tag)"
        }
}

/// 結構化的重複設定：每週選星期幾、每月選幾號、自訂選間隔（原本是自由文字）。
private struct RepeatSettingsView: View {
    @Binding var setting: RepeatSetting

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("重複", selection: $setting.frequency) {
                ForEach(RepeatFrequency.allCases) { Text($0.label).tag($0) }
            }

            switch setting.frequency {
            case .none:
                EmptyView()
            case .weekly:
                Picker("星期", selection: $setting.weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text("週\(RepeatSetting.weekdayNames[day - 1])").tag(day)
                    }
                }
                .pickerStyle(.segmented)
            case .monthly:
                Picker("每月幾號", selection: $setting.dayOfMonth) {
                    ForEach(1...28, id: \.self) { day in
                        Text("\(day) 日").tag(day)
                    }
                }
            case .custom:
                HStack {
                    Picker("間隔", selection: $setting.interval) {
                        ForEach(2...12, id: \.self) { value in
                            Text("每 \(value)").tag(value)
                        }
                    }
                    Picker("單位", selection: $setting.unit) {
                        ForEach(CustomRepeatUnit.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if setting.frequency != .none {
                Text("將以「\(setting.label)」建立週期規則；之後由後端依規則產生每期交易。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - AI Capture Sheets (mock)

private struct VoiceCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentMemberID: UUID
    let onSave: (TransactionItem) -> Void

    @State private var phrase = "買了一杯飲料 30 塊"
    @State private var isParsing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                MockAPIHero(icon: "waveform", color: .teal, isParsing: isParsing)

                TextField("語音內容 mock，例如 買了一杯飲料 30 塊", text: $phrase, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 10) {
                    Label("需要 API：語音轉文字 + AI 分類解析", systemImage: "network")
                    Label("Mock result: 飲料 / 30 / 食 / 共同帳戶", systemImage: "sparkles")
                    Label("成功後直接入帳；錯了左滑修改或刪除", systemImage: "arrow.left")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button {
                    parseWithMockAPI()
                } label: {
                    Label(isParsing ? "Mock API 解析中" : "Call Mock API 入帳", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isParsing)

                Spacer()
            }
            .padding(20)
            .navigationTitle("AI 語音記帳")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private func parseWithMockAPI() {
        isParsing = true
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            await MainActor.run {
                onSave(TransactionItem(
                    title: "飲料",
                    amount: 30,
                    date: .now,
                    category: .food,
                    account: .shared,
                    recorderID: currentMemberID,
                    tags: ["#AI", "#語音"],
                    source: .voice
                ))
                dismiss()
            }
        }
    }
}

private struct PhotoCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentMemberID: UUID
    let onSave: (TransactionItem) -> Void

    @State private var isParsing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                MockAPIHero(icon: "doc.viewfinder.fill", color: .indigo, isParsing: isParsing)

                VStack(alignment: .leading, spacing: 10) {
                    Label("需要 API：收據 OCR + AI 分類解析", systemImage: "network")
                    Label("Mock receipt: 全聯採買 / 1,268 / 食 / 共同帳戶", systemImage: "sparkles")
                    Label("API 成功後才建立正式帳目", systemImage: "checkmark.seal.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.title)
                            Text("Receipt photo placeholder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                Button {
                    parseWithMockAPI()
                } label: {
                    Label(isParsing ? "Mock API 解析中" : "拍照並解析", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isParsing)

                Spacer()
            }
            .padding(20)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("相片記帳")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private func parseWithMockAPI() {
        isParsing = true
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            await MainActor.run {
                onSave(TransactionItem(
                    title: "全聯採買",
                    amount: 1_268,
                    date: .now,
                    category: .food,
                    account: .shared,
                    recorderID: currentMemberID,
                    tags: ["#AI", "#收據"],
                    source: .receipt
                ))
                dismiss()
            }
        }
    }
}

private struct MockAPIHero: View {
    let icon: String
    let color: Color
    let isParsing: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 120, height: 120)
            if isParsing {
                ProgressView()
                    .tint(color)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Projects

private struct ProjectsView: View {
    var store: AppStore
    @Binding var selectedProject: ProjectDefinition?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.projects) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        ProjectCard(
                            project: project,
                            spent: store.projectSpent(project),
                            count: store.projectCount(project)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("專案追蹤")
    }
}

private struct ProjectCard: View {
    let project: ProjectDefinition
    let spent: Int
    let count: Int

    private var progress: Double {
        guard project.budget > 0 else { return 0 }
        return min(Double(spent) / Double(project.budget), 1.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.headline)
                    Text("\(project.tag) · \(project.status.label) · \(count) 筆")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if project.isFixed {
                    TagChip(text: "固定型", color: .blue)
                }
            }

            ProgressView(value: progress, total: 1)
                .tint(progress > 1 ? .red : .teal)
            HStack {
                Text("Spent \(currency(spent))")
                Spacer()
                Text("Budget \(currency(project.budget))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectDetailView: View {
    var store: AppStore
    let project: ProjectDefinition

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                ProjectCard(
                    project: project,
                    spent: store.projectSpent(project),
                    count: store.projectCount(project)
                )
                Text("每月長條圖")
                    .font(.headline)
                MonthlyBars(values: store.projectMonthly(project))
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(project.title)
        }
    }
}

// MARK: - Budget

private struct BudgetView: View {
    var store: AppStore

    private var categorySpending: [ExpenseCategory: Int] {
        store.categorySpendingThisMonth
    }

    private var totalSpent: Int {
        categorySpending.values.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("總預算進度")
                            .font(.headline)
                        Spacer()
                        Text("\(currency(totalSpent)) / \(currency(store.budget.total))")
                            .font(.headline.monospacedDigit())
                    }
                    BudgetProgressBar(
                        spentRatio: store.budget.total > 0 ? Double(totalSpent) / Double(store.budget.total) : 0,
                        dayRatio: store.dayProgress
                    )
                    Text("灰線為照日期進度基準線；超支不阻擋，只提示。統計範圍：本月共同帳。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                ForEach(ExpenseCategory.allCases) { category in
                    let spent = categorySpending[category, default: 0]
                    let limit = store.budget.categoryLimits[category, default: 0]
                    CategoryBudgetRow(category: category, spent: spent, limit: limit)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("預算")
    }
}

// MARK: - Reports

private struct ReportsView: View {
    var store: AppStore

    /// 本月共同帳的分類佔比（由真實交易計算，不再寫死）。
    private var breakdown: [(category: ExpenseCategory, amount: Int)] {
        store.categorySpendingThisMonth
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
    }

    private var total: Int { breakdown.map(\.amount).reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("本月分類佔比（共同帳）")
                        .font(.headline)
                    if total == 0 {
                        Text("本月還沒有共同帳支出")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        DonutChart(items: breakdown, total: total)
                            .frame(width: 190, height: 190)
                            .frame(maxWidth: .infinity)

                        VStack(spacing: 8) {
                            ForEach(breakdown, id: \.category) { item in
                                HStack {
                                    Circle()
                                        .fill(item.category.color)
                                        .frame(width: 8, height: 8)
                                    Text(item.category.label)
                                        .font(.caption)
                                    Spacer()
                                    Text(currency(item.amount))
                                        .font(.caption.monospacedDigit())
                                    Text("\(Int((Double(item.amount) / Double(total) * 100).rounded()))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 42, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 12) {
                    Text("本月成員分攤（共同帳）")
                        .font(.headline)
                    let split = store.memberSplitThisMonth()
                    SegmentedBar(entries: split.map { ($0.member.color.color, $0.total) })
                    HStack {
                        ForEach(split, id: \.member.id) { entry in
                            LegendTotal(name: entry.member.initial, amount: entry.total, color: entry.member.color.color)
                            if entry.member.id != split.last?.member.id {
                                Spacer()
                            }
                        }
                    }
                }
                .padding(16)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 12) {
                    Text("近 6 個月趨勢（共同帳）")
                        .font(.headline)
                    MonthlyBars(values: store.monthlyTrend(), highlightLast: true)
                }
                .padding(16)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("報表")
    }
}

/// 分類佔比圓環：依實際金額切扇形。
private struct DonutChart: View {
    let items: [(category: ExpenseCategory, amount: Int)]
    let total: Int

    private var segments: [(color: Color, from: Double, to: Double)] {
        var running = 0.0
        return items.map { item in
            let fraction = Double(item.amount) / Double(max(total, 1))
            let segment = (item.category.color, running, running + fraction)
            running += fraction
            return segment
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Circle()
                    .trim(from: segment.from, to: segment.to)
                    .stroke(segment.color, lineWidth: 24)
                    .rotationEffect(.degrees(-90))
            }
            VStack {
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currency(total))
                    .font(.title3.bold().monospacedDigit())
            }
        }
        .padding(12)
    }
}

// MARK: - Shared Components

private struct RecorderBadge: View {
    let recorder: Member?

    var body: some View {
        Text(recorder?.initial ?? "?")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(recorder?.color.color ?? .gray)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct TagChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct LegendTotal: View {
    let name: String
    let amount: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
            Text(currency(amount))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// 多段比例條：支援任意數量成員（原本只能兩人）。
private struct SegmentedBar: View {
    let entries: [(color: Color, value: Int)]

    private var total: Int {
        max(entries.map(\.value).reduce(0, +), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    entry.color
                        .frame(width: proxy.size.width * Double(entry.value) / Double(total))
                }
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
            .background(Capsule().fill(Color(.systemGray5)))
        }
        .frame(height: 12)
    }
}

private struct CategoryButton: View {
    let category: ExpenseCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: category.icon)
                Text(category.label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(isSelected ? .white : category.color)
            .background(isSelected ? category.color : category.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct BudgetProgressBar: View {
    let spentRatio: Double
    let dayRatio: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule()
                    .fill(spentRatio > 1 ? .red : .teal)
                    .frame(width: proxy.size.width * min(spentRatio, 1))
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 2, height: 28)
                    .offset(x: proxy.size.width * min(dayRatio, 1))
            }
        }
        .frame(height: 18)
    }
}

private struct CategoryBudgetRow: View {
    let category: ExpenseCategory
    let spent: Int
    let limit: Int

    private var ratio: Double {
        guard limit > 0 else { return 0 }
        return Double(spent) / Double(limit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(category.label, systemImage: category.icon)
                    .font(.headline)
                Spacer()
                Text("\(currency(spent)) / \(currency(limit))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(ratio, 1))
                .tint(ratio > 1 ? .red : ratio > 0.85 ? .orange : .teal)
            if ratio > 1 {
                Text("已超支 \(currency(spent - limit))")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            } else if ratio > 0.85 {
                Text("接近上限")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.background)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(ratio > 1 ? .red : .clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// 每月長條圖：金額依最大值正規化（原本用固定除數，容易爆版面）。
private struct MonthlyBars: View {
    let values: [(label: String, total: Int)]
    var highlightLast = false

    private var maxValue: Int {
        max(values.map(\.total).max() ?? 1, 1)
    }

    var body: some View {
        if values.isEmpty {
            Text("尚無資料")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(highlightLast && index == values.count - 1 ? .teal : Color.gray.opacity(0.35))
                            .frame(height: max(CGFloat(value.total) / CGFloat(maxValue) * 140, value.total > 0 ? 8 : 2))
                        Text(value.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 170)
        }
    }
}

#Preview {
    ContentView()
}
