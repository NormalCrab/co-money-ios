import MMCore
import SwiftUI

/// 預算金額的輸入：空白是「不設預算」；填了就必須是不小於 0 的數字。
private func parseBudget(_ text: String) -> (value: Money?, isValid: Bool) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return (nil, true) }
    guard let money = Money(userInput: trimmed), money.value >= 0 else { return (nil, false) }
    return (money, true)
}

/// 執行一個需要連線的寫入，失敗時回傳給使用者看的訊息。
@MainActor
private func perform(_ work: () async throws -> Void) async -> String? {
    do {
        try await work()
        return nil
    } catch let error as APIError {
        return error.message
    } catch {
        return error.localizedDescription
    }
}

/// 新增 / 修改一次性預算（tag）。週期預算的單一期也從這裡改（不影響規則，v2 §5.2）。
///
/// 一次性預算用期限決定顯示（§12.2）：原本的「封存」改成設結束日，「取消封存」改成清掉結束日。
struct BudgetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var editing: Tag?

    @State private var name = ""
    @State private var budgetText = ""
    @State private var hasStart = false
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date()
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDelete = false

    private var isPeriodic: Bool { editing?.isPeriodic == true }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱", text: $name)
                    TextField("預算金額（可以不填）", text: $budgetText).keyboardType(.decimalPad)
                } footer: {
                    if isPeriodic {
                        Text("這是週期預算的其中一期，修改它不會影響規則和其他期。")
                    }
                }

                if isPeriodic, let editing {
                    Section("期限") {
                        LabeledContent("期限", value: DateText.period(start: editing.periodStart,
                                                                     end: editing.periodEnd) ?? "—")
                    }
                } else {
                    periodSection
                }

                if let editing {
                    Section {
                        Button("刪除", role: .destructive) { confirmDelete = true }
                    }
                    .confirmationDialog("刪除「\(editing.name)」？掛在上面的交易不會被刪除。",
                                        isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("刪除", role: .destructive) { Task { await delete(editing) } }
                    }
                }
                FormStatus(error: error, needsConnection: model.isOffline)
            }
            .navigationTitle(editing == nil ? "新增預算" : "修改預算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { Task { await save() } }.bold().disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var periodSection: some View {
        Section {
            Toggle("設定開始日", isOn: $hasStart)
            if hasStart {
                DatePicker("開始日", selection: $startDate, displayedComponents: .date)
            }
            Toggle("設定結束日", isOn: $hasEnd)
            if hasEnd {
                DatePicker("結束日", selection: $endDate, in: (hasStart ? startDate : .distantPast)...,
                           displayedComponents: .date)
            }
        } header: {
            Text("期限")
        } footer: {
            Text("沒有結束日表示一直進行中；結束日過了就算結束（取代原本的「封存」），已經掛上的交易不受影響。旅行可以先設好回程日。")
        }
    }

    private func load() {
        let today = model.today.date(in: model.timeZone)
        guard let editing else {
            startDate = today
            endDate = today
            return
        }
        name = editing.name
        budgetText = editing.budgetAmount?.apiString ?? ""
        hasStart = editing.periodStart != nil
        startDate = editing.periodStart?.date(in: model.timeZone) ?? today
        hasEnd = editing.periodEnd != nil
        // 打開結束日時預設今天，等於原本的「封存」（§12.2）。
        endDate = editing.periodEnd?.date(in: model.timeZone) ?? today
    }

    /// 一次性 tag 的期限；週期 tag 是 nil（期限由規則決定，送了會被拒絕）。
    private var period: TagWrite.Period? {
        guard !isPeriodic else { return nil }
        let tz = model.timeZone
        return .init(start: hasStart ? LocalDate(startDate, in: tz) : nil,
                     end: hasEnd ? LocalDate(endDate, in: tz) : nil)
    }

    private var periodIsValid: Bool {
        guard let start = period?.start, let end = period?.end else { return true }
        return start <= end
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parseBudget(budgetText).isValid
            && periodIsValid && !isSaving && !model.isOffline
    }

    private func save() async {
        guard let ledger = model.selectedLedger else { return }
        isSaving = true
        error = await perform {
            let budget = parseBudget(budgetText).value
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if let editing {
                _ = try await model.api.updateTag(
                    editing.id, with: TagWrite(name: trimmed, budgetAmount: budget, period: period))
            } else {
                _ = try await model.api.createTag(
                    TagWrite(ledgerId: ledger.id, name: trimmed, budgetAmount: budget, period: period))
            }
        }
        await finish()
    }

    private func delete(_ tag: Tag) async {
        isSaving = true
        error = await perform { try await model.api.deleteTag(tag.id) }
        await finish()
    }

    private func finish() async {
        isSaving = false
        guard error == nil else { return }
        await model.refreshLedgerData()
        dismiss()
    }
}

/// 表單底部的狀態：需要連線的提醒、後端的錯誤訊息。
struct FormStatus: View {
    let error: String?
    let needsConnection: Bool

    var body: some View {
        if needsConnection || error != nil {
            Section {
                if needsConnection {
                    Text("設定需要連線。").font(.footnote).foregroundStyle(Palette.warning)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Palette.warning)
                }
            }
        }
    }
}

/// 週期預算規則的清單（v2 §2.6）：依頻率每一期自動產生一個預算。分成進行中、已結束（§12.3）。
struct TagRulesView: View {
    @Environment(AppModel.self) private var model
    @State private var rules: [TagRule] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var editing: TagRule?
    @State private var creating = false

    private var ongoing: [TagRule] { rules.filter { $0.isOngoing(today: model.today) } }
    private var ended: [TagRule] { rules.filter { !$0.isOngoing(today: model.today) } }

    var body: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError).font(.footnote).foregroundStyle(Palette.warning)
                }
            }
            Section {
                ForEach(ongoing) { row($0) }
                if loaded && loadError == nil && rules.isEmpty {
                    Text("還沒有週期預算").foregroundStyle(.secondary)
                }
            }
            if !ended.isEmpty {
                Section("已結束") {
                    ForEach(ended) { row($0) }
                }
            }
        }
        .navigationTitle("週期預算")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { rule in
            TagRuleEditor(editing: rule) { await load() }
        }
        .sheet(isPresented: $creating) {
            TagRuleEditor { await load() }
        }
    }

    private func row(_ rule: TagRule) -> some View {
        Button { editing = rule } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).foregroundStyle(.primary)
                Text(summary(rule)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func summary(_ rule: TagRule) -> String {
        let today = model.today
        var parts = [rule.frequency.label]
        parts.append(rule.budgetAmount.map { "預算 \($0.display)" } ?? "沒有預算金額")
        if rule.startDate > today {
            parts.append("\(DateText.shortDay(rule.startDate, today: today)) 開始")
        }
        if let end = rule.endDate {
            let day = DateText.shortDay(end, today: today)
            parts.append(rule.isOngoing(today: today) ? "到 \(day)" : "\(day) 結束")
        }
        return parts.joined(separator: "・")
    }

    private func load() async {
        guard let ledger = model.selectedLedger else { return }
        loadError = await perform { rules = try await model.api.tagRules(ledger: ledger.id) }
        loaded = true
    }
}

/// 新增 / 修改週期預算規則。頻率建立後不能改。
///
/// 期限（§12.3）：停用 = 設結束日，之後不再產生新的一期，已產生的保留；重新啟用 = 清掉結束日或改晚。
/// 開始日只能往前改（後端會擋往後改）。
struct TagRuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var editing: TagRule?
    var onSaved: () async -> Void = {}

    @State private var name = ""
    @State private var budgetText = ""
    @State private var frequency: Frequency = .monthly
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date()
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱（每一期會加上日期）", text: $name)
                    TextField("每一期的預算（可以不填）", text: $budgetText).keyboardType(.decimalPad)
                    if editing == nil {
                        Picker("頻率", selection: $frequency) {
                            ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                        }
                    } else {
                        LabeledContent("頻率", value: frequency.label)
                    }
                } footer: {
                    Text("修改只影響之後產生的每一期，已經產生的不會變。")
                }

                Section {
                    DatePicker("開始日", selection: $startDate, in: startRange, displayedComponents: .date)
                    Toggle("設定結束日", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("結束日", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("期限")
                } footer: {
                    Text(editing == nil
                         ? "開始日落在一期的中間時，那一整期都算。結束日可以先設在未來，例如只到年底。"
                         : "停用就是設結束日：之後不再產生新的一期，已經產生的都保留。要重新啟用就關掉結束日或改晚。開始日只能往前改。")
                }

                if let editing {
                    Section {
                        Button("刪除規則", role: .destructive) { confirmDelete = true }
                    }
                    .confirmationDialog("刪除「\(editing.name)」？已經產生的每一期會保留，變成一次性預算。",
                                        isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("刪除規則", role: .destructive) { Task { await delete(editing) } }
                    }
                }
                FormStatus(error: error, needsConnection: model.isOffline)
            }
            .navigationTitle(editing == nil ? "新增週期預算" : "修改週期預算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { Task { await save() } }.bold().disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    /// 修改時開始日只能往前（後端會擋往後改）。
    private var startRange: ClosedRange<Date> {
        Date.distantPast...(editing?.startDate.date(in: model.timeZone) ?? .distantFuture)
    }

    private func load() {
        let today = model.today.date(in: model.timeZone)
        guard let editing else {
            startDate = today
            endDate = today
            return
        }
        name = editing.name
        budgetText = editing.budgetAmount?.apiString ?? ""
        frequency = editing.frequency
        startDate = editing.startDate.date(in: model.timeZone)
        hasEnd = editing.endDate != nil
        endDate = editing.endDate?.date(in: model.timeZone) ?? max(today, startDate)
    }

    private var start: LocalDate { LocalDate(startDate, in: model.timeZone) }
    private var end: LocalDate? { hasEnd ? LocalDate(endDate, in: model.timeZone) : nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parseBudget(budgetText).isValid
            && (end.map { $0 >= start } ?? true) && !isSaving && !model.isOffline
    }

    private func save() async {
        guard let ledger = model.selectedLedger else { return }
        isSaving = true
        error = await perform {
            let budget = parseBudget(budgetText).value
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if let editing {
                _ = try await model.api.updateTagRule(
                    editing.id, with: TagRuleWrite(name: trimmed, budgetAmount: budget, frequency: frequency,
                                                   startDate: start, endDate: end))
            } else {
                _ = try await model.api.createTagRule(
                    TagRuleWrite(ledgerId: ledger.id, name: trimmed, budgetAmount: budget, frequency: frequency,
                                 startDate: start, endDate: end))
            }
        }
        await finish()
    }

    private func delete(_ rule: TagRule) async {
        isSaving = true
        error = await perform { try await model.api.deleteTagRule(rule.id) }
        await finish()
    }

    private func finish() async {
        isSaving = false
        guard error == nil else { return }
        await model.refreshLedgerData()  // 新規則可能已經產生了當期的 tag
        await onSaved()
        dismiss()
    }
}
