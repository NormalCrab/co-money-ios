import MMCore
import SwiftUI

/// 確認解析結果（§0 原則 3：LLM 的結果一律經過使用者確認）。
///
/// 每筆的交易 `id` 在第一次顯示時就決定好，之後確認重送都用同一個（§3.1）。
struct DraftReview: View {
    @Environment(AppModel.self) private var model
    let job: ParseJob
    /// 區塊標題的前半，例如「待確認・語音・昨天 21:05 記錄」。
    var title: String?
    var onFinish: () -> Void = {}

    @State private var items: [Item] = []
    @State private var editing: Item?

    struct Item: Identifiable, Hashable {
        var input: TransactionInput
        var included = true
        var id: UUID { input.id }
    }

    var body: some View {
        Section {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Button {
                        toggle(item)
                    } label: {
                        Image(systemName: item.included ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.included ? Palette.accent : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    CategoryIcon(category: item.input.category)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.input.description)
                        Text(meta(item.input)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let shown = item.input.displayAmount {
                        Text([shown.1, shown.0.display].compactMap { $0 }.joined(separator: " "))
                            .font(.body.monospacedDigit())
                    } else {
                        Text("請填金額").font(.caption).foregroundStyle(Palette.warning)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = item }
            }
        } header: {
            let ledger = model.ledgers.first { $0.id == job.ledgerId }?.name ?? ""
            Text([title, ledger, "點一下可以修改"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "・"))
        } footer: {
            if job.source != .receipt, !job.text.isEmpty {
                Text("原文：\(job.text)")
            }
        }

        Section {
            Button {
                Task { await confirm() }
            } label: {
                Text("加入 \(selected.count) 筆").bold().frame(maxWidth: .infinity)
            }
            .disabled(selected.isEmpty || selected.contains { $0.amount == nil && $0.originalAmount == nil })
            Button("全部捨棄", role: .destructive) {
                Task {
                    await model.discard(job)
                    onFinish()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if items.isEmpty { items = job.drafts.map { Item(input: $0.input()) } }
        }
        .sheet(item: $editing) { item in
            DraftEditor(input: item.input) { updated in
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].input = updated }
            }
        }
    }

    private var selected: [TransactionInput] { items.filter(\.included).map(\.input) }

    private func toggle(_ item: Item) {
        guard let index = items.firstIndex(of: item) else { return }
        items[index].included.toggle()
    }

    private func meta(_ input: TransactionInput) -> String {
        let timeZone = model.ledgers.first { $0.id == input.ledgerId }?.timeZone ?? model.timeZone
        let day = LocalDate(input.transactionDate, in: timeZone)
        var parts = [input.category.label, DateText.shortDay(day, today: LocalDate(Date(), in: timeZone))]
        if let notes = input.notes { parts.append("備註：\(notes)") }
        return parts.joined(separator: "・")
    }

    private func confirm() async {
        await model.confirm(job, transactions: selected)
        onFinish()
    }
}

/// 修改一筆解析結果。
struct DraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var input: TransactionInput
    let onSave: (TransactionInput) -> Void

    @State private var amountText = ""
    @State private var originalText = ""
    @State private var initialAmount = ""
    @State private var initialOriginal = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("類型", selection: $input.transactionType) {
                    Text("支出").tag(TransactionType.expense)
                    Text("收入").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                TextField("描述", text: $input.description)
                if let currency = input.originalCurrency {
                    // 外幣：原幣金額必填；換算後的金額可以空著，由後端用帳本匯率算。
                    // 帳本沒有這個幣別的匯率時，要填換算後的金額（v2 §4.3）。
                    Section {
                        LabeledContent("\(currency) 金額") {
                            TextField("0", text: $originalText).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("換算後") {
                            TextField("用帳本匯率", text: $amountText).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    } footer: {
                        Text("帳本沒有設定 \(currency) 匯率時，請填換算後的金額。")
                    }
                } else {
                    LabeledContent("金額") {
                        TextField("0", text: $amountText).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Picker("分類", selection: $input.category) {
                    ForEach(TransactionCategory.allCases) { Text($0.label).tag($0) }
                }
                DatePicker("日期", selection: $input.transactionDate)
                TextField("備註", text: Binding(get: { input.notes ?? "" },
                                               set: { input.notes = $0.isEmpty ? nil : $0 }))
            }
            .navigationTitle("修改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        input.amount = Money(userInput: amountText)
                        if input.originalCurrency != nil {
                            input.originalAmount = Money(userInput: originalText)
                            // 只改了原幣金額、沒動換算後的金額：舊的換算結果已經不對，
                            // 清掉讓後端用帳本匯率重算。
                            if originalText != initialOriginal && amountText == initialAmount {
                                input.amount = nil
                            }
                        }
                        onSave(input)
                        dismiss()
                    }
                }
            }
            .onAppear {
                initialAmount = input.amount?.apiString ?? ""
                initialOriginal = input.originalAmount?.apiString ?? ""
                amountText = initialAmount
                originalText = initialOriginal
            }
        }
    }
}

/// 送出解析並在畫面上等結果（§2.2）。好了就顯示確認，等不到就告訴使用者結果之後會出現在「待處理」。
struct ParseProgress: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let upload: ParseJobUpload

    @State private var job: ParseJob?
    @State private var finishedWaiting = false
    @State private var retryError: String?

    var body: some View {
        Form {
            if let job, job.status == .done {
                DraftReview(job: job) { dismiss() }
            } else if let job, job.status == .failed {
                Section {
                    Label(job.error.isEmpty ? "解析失敗" : job.error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.warning)
                    if let retryError {
                        Text(retryError).font(.caption).foregroundStyle(Palette.warning)
                    }
                    Button("重試") {
                        Task {
                            // 只請後端重跑，不重新上傳（附件在第一次送出後已經刪掉了）。
                            retryError = await model.retry(job)
                            if retryError != nil { return }
                            self.job = nil
                            finishedWaiting = false
                            self.job = await model.waitForParse(job.id)
                            finishedWaiting = true
                        }
                    }
                    .disabled(model.isOffline)
                    Button("捨棄", role: .destructive) {
                        Task {
                            await model.discard(job)
                            dismiss()
                        }
                    }
                }
            } else if finishedWaiting {
                Section {
                    Label(stillQueued ? "已經存起來，連線後自動送出解析。" : "還在解析，好了會出現在首頁的「待處理」。",
                          systemImage: "tray.and.arrow.down")
                    Button("好") { dismiss() }
                }
            } else {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("解析中…")
                    }
                }
            }
        }
        .task { await wait() }
    }

    /// 解析工作還在待上傳佇列裡（離線，或伺服器暫時送不出去）。
    private var stillQueued: Bool {
        model.isOffline || model.outboxItems.contains { $0.operation == .createParseJob(upload) }
    }

    private func wait() async {
        guard job == nil, !finishedWaiting else { return }
        job = await model.submitParse(upload)
        finishedWaiting = true
    }
}
