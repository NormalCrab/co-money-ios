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
struct BudgetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var editing: Tag?
    var onSaved: () async -> Void = {}

    @State private var name = ""
    @State private var budgetText = ""
    @State private var archived = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱", text: $name)
                    TextField("預算金額（可以不填）", text: $budgetText).keyboardType(.decimalPad)
                } footer: {
                    if editing?.isPeriodic == true {
                        Text("這是週期預算的其中一期，修改它不會影響規則和其他期。")
                    }
                }
                if let editing {
                    Section {
                        Toggle("封存", isOn: $archived)
                    } footer: {
                        Text("封存後不會出現在預設的清單；已經掛上的交易不受影響。")
                    }
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
            .onAppear {
                guard let editing else { return }
                name = editing.name
                budgetText = editing.budgetAmount?.apiString ?? ""
                archived = editing.isArchived ?? false
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parseBudget(budgetText).isValid
            && !isSaving && !model.isOffline
    }

    private func save() async {
        guard let ledger = model.selectedLedger else { return }
        isSaving = true
        error = await perform {
            let budget = parseBudget(budgetText).value
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if let editing {
                _ = try await model.api.updateTag(
                    editing.id, with: TagWrite(name: trimmed, budgetAmount: budget, isArchived: archived))
            } else {
                _ = try await model.api.createTag(TagWrite(ledgerId: ledger.id, name: trimmed, budgetAmount: budget))
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
        await onSaved()
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

/// 週期預算規則的清單（v2 §2.6）：依頻率每一期自動產生一個預算。
struct TagRulesView: View {
    @Environment(AppModel.self) private var model
    @State private var rules: [TagRule] = []
    @State private var loaded = false
    @State private var editing: TagRule?
    @State private var creating = false

    var body: some View {
        List {
            ForEach(rules) { rule in
                Button { editing = rule } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name).foregroundStyle(.primary)
                        Text(summary(rule)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if loaded && rules.isEmpty {
                Text("還沒有週期預算").foregroundStyle(.secondary)
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

    private func summary(_ rule: TagRule) -> String {
        var parts = [rule.frequency.label]
        parts.append(rule.budgetAmount.map { "預算 \($0.display)" } ?? "沒有預算金額")
        if !rule.isActive { parts.append("已停用") }
        return parts.joined(separator: "・")
    }

    private func load() async {
        guard let ledger = model.selectedLedger else { return }
        if let list = try? await model.api.tagRules(ledger: ledger.id) { rules = list }
        loaded = true
    }
}

/// 新增 / 修改週期預算規則。頻率建立後不能改；停用只是不再產生新的一期，已產生的保留。
struct TagRuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var editing: TagRule?
    var onSaved: () async -> Void = {}

    @State private var name = ""
    @State private var budgetText = ""
    @State private var frequency: Frequency = .monthly
    @State private var isActive = true
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
                if let editing {
                    Section {
                        Toggle("啟用", isOn: $isActive)
                    } footer: {
                        Text("停用後不再產生新的一期，已經產生的預算都保留。")
                    }
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
            .onAppear {
                guard let editing else { return }
                name = editing.name
                budgetText = editing.budgetAmount?.apiString ?? ""
                frequency = editing.frequency
                isActive = editing.isActive
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parseBudget(budgetText).isValid
            && !isSaving && !model.isOffline
    }

    private func save() async {
        guard let ledger = model.selectedLedger else { return }
        isSaving = true
        error = await perform {
            let budget = parseBudget(budgetText).value
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if let editing {
                _ = try await model.api.updateTagRule(
                    editing.id, with: TagRuleWrite(name: trimmed, budgetAmount: budget,
                                                   frequency: frequency, isActive: isActive))
            } else {
                _ = try await model.api.createTagRule(
                    TagRuleWrite(ledgerId: ledger.id, name: trimmed, budgetAmount: budget, frequency: frequency))
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
