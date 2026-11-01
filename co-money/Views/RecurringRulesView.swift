import MMCore
import SwiftUI

extension LocalDate {
    /// 這一天在這個時區的正午（DatePicker 用；取正午避免夏令時間的邊界問題）。
    func date(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }
}

private let weekdayNames = ["週一", "週二", "週三", "週四", "週五", "週六", "週日"]

/// 這條規則的排程說明：「每月 5 日」「每週三」「每年 10 月 5 日」。
private func scheduleText(frequency: Frequency, day: Int, startMonth: Int) -> String {
    switch frequency {
    case .weekly: "每" + weekdayNames[min(max(day, 1), 7) - 1]
    case .monthly: "每月 \(day) 日"
    case .yearly: "每年 \(startMonth) 月 \(day) 日"
    }
}

/// 重複交易規則的清單（N8、v2 §2.7）：房租、訂閱這類固定的帳，到期由後端自動產生交易。
struct RecurringRulesView: View {
    @Environment(AppModel.self) private var model
    @State private var rules: [RecurringRule] = []
    @State private var loaded = false
    @State private var editing: RecurringRule?
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            List {
                ForEach(rules) { rule in
                    Button { editing = rule } label: { row(rule) }
                }
                if loaded && rules.isEmpty {
                    Text("還沒有重複交易，按右上角的「＋」新增。").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("重複交易")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { rule in
            RecurringRuleEditor(editing: rule) { await load() }
        }
        .sheet(isPresented: $creating) {
            RecurringRuleEditor { await load() }
        }
    }

    private func row(_ rule: RecurringRule) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: rule.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.description).foregroundStyle(.primary)
                Text(detail(rule)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountText(rule)).font(.body.monospacedDigit()).foregroundStyle(.primary)
        }
        .opacity(rule.isActive ? 1 : 0.5)
    }

    private func amountText(_ rule: RecurringRule) -> String {
        if let original = rule.originalAmount, let currency = rule.originalCurrency {
            return "\(currency) \(original.display)"
        }
        return (rule.amount ?? .zero).signed(for: rule.transactionType)
    }

    private func detail(_ rule: RecurringRule) -> String {
        var parts = [scheduleText(frequency: rule.frequency, day: rule.day, startMonth: rule.startDate.month)]
        parts.append(rule.isActive ? "下次 \(rule.nextRunDate.month)/\(rule.nextRunDate.day)" : "已停用")
        return parts.joined(separator: "・")
    }

    private func load() async {
        guard let ledger = model.selectedLedger else { return }
        if let list = try? await model.api.recurringRules(ledger: ledger.id) { rules = list }
        loaded = true
    }
}

/// 新增 / 修改重複交易規則。付款人固定是建立者；帳本建立後不能換。
struct RecurringRuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var editing: RecurringRule?
    var onSaved: () async -> Void = {}

    @State private var description = ""
    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var currency = ""
    @State private var category: TransactionCategory = .housing
    @State private var notes = ""
    @State private var frequency: Frequency = .monthly
    @State private var day = 1
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date()
    @State private var tagIds: Set<UUID> = []
    @State private var isActive = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDelete = false

    private var baseCurrency: String {
        editing?.ledger.baseCurrency ?? model.selectedLedger?.currency ?? "TWD"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("描述（例如：房租）", text: $description)
                    Picker("類型", selection: $type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        TextField("金額", text: $amountText).keyboardType(.decimalPad)
                        Picker("幣別", selection: $currency) {
                            ForEach(Currencies.options(base: baseCurrency), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                    Picker("分類", selection: $category) {
                        ForEach(TransactionCategory.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("備註", text: $notes)
                } footer: {
                    if currency != baseCurrency {
                        Text("外幣會在每次產生交易時，依帳本當時的匯率換算。")
                    }
                }

                Section {
                    Picker("頻率", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                    }
                    if frequency == .weekly {
                        Picker("星期", selection: $day) {
                            ForEach(1...7, id: \.self) { Text(weekdayNames[$0 - 1]).tag($0) }
                        }
                    } else {
                        Picker("日期", selection: $day) {
                            ForEach(1...31, id: \.self) { Text("\($0) 日").tag($0) }
                        }
                    }
                    DatePicker("開始", selection: $startDate, displayedComponents: .date)
                        .environment(\.timeZone, model.timeZone)
                    Toggle("設定結束日期", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("結束", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .environment(\.timeZone, model.timeZone)
                    }
                } header: {
                    Text("排程")
                } footer: {
                    Text(scheduleSummary + (frequency == .monthly || frequency == .yearly
                                            ? "。遇到較短的月份，會用該月最後一天。" : "。"))
                }

                if !tagChoices.isEmpty {
                    Section("Tag") {
                        ForEach(tagChoices) { tag in
                            Button {
                                if tagIds.contains(tag.id) { tagIds.remove(tag.id) } else { tagIds.insert(tag.id) }
                            } label: {
                                HStack {
                                    Text(tag.name).foregroundStyle(.primary)
                                    Spacer()
                                    if tagIds.contains(tag.id) {
                                        Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                if let editing {
                    Section {
                        Toggle("啟用", isOn: $isActive)
                        Text("付款人：\(editing.payer.username)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("刪除規則", role: .destructive) { confirmDelete = true }
                    }
                    .confirmationDialog("刪除「\(editing.description)」？已經產生的交易會保留。",
                                        isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("刪除規則", role: .destructive) { Task { await delete(editing) } }
                    }
                } else {
                    Section {
                        Text("付款人是你自己。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                FormStatus(error: error, needsConnection: model.isOffline)
            }
            .navigationTitle(editing == nil ? "新增重複交易" : "修改重複交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { Task { await save() } }.bold().disabled(write == nil || isSaving || model.isOffline)
                }
            }
            .onAppear(perform: load)
            .onChange(of: frequency) { _, new in
                // 每週的 day 是 1–7；從每月切過來時要拉回合法範圍。
                if new == .weekly { day = min(max(day, 1), 7) }
            }
        }
    }

    private var scheduleSummary: String {
        let month = LocalDate(startDate, in: model.timeZone).month
        return scheduleText(frequency: frequency, day: day, startMonth: month)
    }

    /// 規則可以掛任何一期的 tag（產生交易時後端會換成涵蓋當天的那一期）。
    private var tagChoices: [Tag] { model.tags }

    private var write: RecurringRuleWrite? {
        let trimmed = description.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let amount = Money(userInput: amountText), amount.value > 0 else { return nil }
        let tz = model.timeZone
        let start = LocalDate(startDate, in: tz)
        let end = hasEnd ? LocalDate(endDate, in: tz) : nil
        if let end, end < start { return nil }
        let isForeign = currency != baseCurrency
        return RecurringRuleWrite(
            ledgerId: editing == nil ? model.selectedLedger?.id : nil,
            description: trimmed, transactionType: type, category: category, notes: notes,
            amount: isForeign ? nil : amount,
            originalAmount: isForeign ? amount : nil,
            originalCurrency: isForeign ? currency : nil,
            tags: Array(tagIds), frequency: frequency, day: day,
            startDate: start, endDate: end, isActive: isActive)
    }

    private func load() {
        guard let editing else {
            currency = currency.isEmpty ? baseCurrency : currency
            return
        }
        let tz = model.timeZone
        description = editing.description
        type = editing.transactionType
        category = editing.category
        notes = editing.notes ?? ""
        frequency = editing.frequency
        day = editing.day
        startDate = editing.startDate.date(in: tz)
        hasEnd = editing.endDate != nil
        endDate = editing.endDate?.date(in: tz) ?? startDate
        tagIds = Set(editing.tags)
        isActive = editing.isActive
        if let original = editing.originalAmount, let originalCurrency = editing.originalCurrency {
            amountText = original.apiString
            currency = originalCurrency
        } else {
            amountText = editing.amount?.apiString ?? ""
            currency = baseCurrency
        }
    }

    private func save() async {
        guard let write else { return }
        isSaving = true
        error = await run {
            if let editing {
                _ = try await model.api.updateRecurringRule(editing.id, with: write)
            } else {
                _ = try await model.api.createRecurringRule(write)
            }
        }
        await finish()
    }

    private func delete(_ rule: RecurringRule) async {
        isSaving = true
        error = await run { try await model.api.deleteRecurringRule(rule.id) }
        await finish()
    }

    private func run(_ work: () async throws -> Void) async -> String? {
        do {
            try await work()
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    private func finish() async {
        isSaving = false
        guard error == nil else { return }
        await onSaved()
        dismiss()
    }
}
