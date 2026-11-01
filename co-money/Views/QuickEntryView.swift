import MMCore
import SwiftUI

/// 記一筆（設計畫布「QuickEntry」）。存進待上傳後立刻關掉，不等網路（§0 原則 2）。
///
/// 傳入 `editing` 時是修改已上傳的交易（N9）：同一個表單，但需要連線，存好之後才關掉。
struct QuickEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var editing: MMCore.Transaction?
    @State private var isSaving = false
    @State private var saveError: String?

    @State private var ledgerId: UUID?
    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var currency = ""
    @State private var category: TransactionCategory = .food
    @State private var description = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var tagIds: Set<UUID> = []
    @State private var didSave = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if model.ledgers.count > 1 && editing == nil {
                    Picker("帳本", selection: $ledgerId) {
                        ForEach(model.ledgers) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("類型", selection: $type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        TextField("金額", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .focused($amountFocused)
                        Picker("幣別", selection: $currency) {
                            ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(editing != nil)  // 已上傳交易的幣別不能改（換算由後端決定）
                    }
                }

                Section("分類") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(TransactionCategory.allCases) { item in
                            Button { category = item } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: item.symbol)
                                    Text(item.label).font(.caption)
                                }
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(item == category ? Palette.accentText : .primary)
                                .background(item == category ? Palette.accentSoft : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(item == category ? Palette.accent : Palette.border,
                                            lineWidth: item == category ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("描述（例如：午餐便當）", text: $description)
                    DatePicker("日期", selection: $date)
                    TextField("備註", text: $notes)
                }

                if !availableTags.isEmpty {
                    Section("Tag") {
                        ForEach(availableTags) { tag in
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

                Section {
                    if let editing {
                        Text("付款人：\(editing.payer.username)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("付款人是你自己。重複交易在「我 → 重複交易」設定。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if editing != nil && model.isOffline {
                        Text("修改已上傳的交易需要連線。").font(.footnote).foregroundStyle(Palette.warning)
                    }
                    if let saveError {
                        Text(saveError).font(.footnote).foregroundStyle(Palette.warning)
                    }
                }
            }
            .navigationTitle(editing == nil ? "記一筆" : "修改交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save).bold()
                        .disabled(input == nil || isSaving || (editing != nil && model.isOffline))
                }
            }
            .onAppear {
                if let editing {
                    load(editing)
                    return
                }
                ledgerId = ledgerId ?? model.selectedLedger?.id
                currency = currency.isEmpty ? ledger?.currency ?? "TWD" : currency
                amountFocused = true
            }
            .onChange(of: ledgerId) { _, _ in
                guard editing == nil else { return }
                currency = ledger?.currency ?? "TWD"
                tagIds = []
            }
            .onChange(of: date) { _, _ in
                // 週期 tag 只能掛期間內的交易（v2 §4.5）：日期改了就拿掉不涵蓋的。
                tagIds = tagIds.filter { id in availableTags.contains { $0.id == id } }
            }
        }
    }

    private var ledger: Ledger? { model.ledgers.first { $0.id == ledgerId } }

    private var currencyOptions: [String] {
        Currencies.options(base: ledger?.currency ?? "TWD")
    }

    /// 只列出目前帳本、涵蓋選定日期的 tag。
    private var availableTags: [Tag] {
        guard ledgerId == model.selectedLedger?.id, let ledger else { return [] }
        let day = LocalDate(date, in: ledger.timeZone)
        return model.tags.filter { $0.covers(day) }
    }

    private var input: TransactionInput? {
        guard let ledger, let amount = Money(userInput: amountText), amount.value > 0 else { return nil }
        let isForeign = currency != ledger.currency
        let text = description.trimmingCharacters(in: .whitespaces)
        return TransactionInput(
            id: editing?.id ?? UUID(),
            ledgerId: ledger.id,
            description: text.isEmpty ? category.label : text,
            transactionType: type,
            category: category,
            transactionDate: date,
            amount: isForeign ? nil : amount,
            originalAmount: isForeign ? amount : nil,
            originalCurrency: isForeign ? currency : nil,
            notes: notes.isEmpty ? nil : notes,
            tagIds: Array(tagIds))
    }

    /// 把已上傳的交易填進表單。外幣交易顯示原幣金額和幣別。
    private func load(_ transaction: MMCore.Transaction) {
        ledgerId = transaction.ledger.id
        type = transaction.transactionType
        category = transaction.category
        description = transaction.description
        date = transaction.transactionDate
        notes = transaction.notes ?? ""
        tagIds = Set(transaction.tags.map(\.id))
        if let original = transaction.originalAmount, let originalCurrency = transaction.originalCurrency {
            amountText = original.apiString
            currency = originalCurrency
        } else {
            amountText = transaction.amount?.apiString ?? ""
            currency = transaction.currency ?? transaction.ledger.baseCurrency ?? "TWD"
        }
    }

    private func save() {
        // 連點兩下儲存不能產生兩筆：`input` 每次讀都會產生新的 id。
        guard !didSave, let input else { return }
        if let editing {
            isSaving = true
            saveError = nil
            Task {
                do {
                    try await model.update(editing, with: input)
                    dismiss()
                } catch let error as APIError {
                    saveError = error.message
                    isSaving = false
                } catch {
                    saveError = error.localizedDescription
                    isSaving = false
                }
            }
            return
        }
        didSave = true
        dismiss()
        Task { await model.add(input) }
    }
}
