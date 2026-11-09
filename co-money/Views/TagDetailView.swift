import MMCore
import SwiftUI

/// tag 明細（v2-design §12.10）：上面是預算進度，下面是掛了這個 tag 的全部交易。
///
/// 從首頁的預算卡或預算分頁點進來。交易不限月份（tag 的期限可能跨月），需要連線；
/// 離線時先顯示這個月已經載入的交易。修改 tag 在右上角，刪掉 tag 後自動回上一頁。
struct TagDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// 點進來時的 tag；之後以 `model.tags` 裡的最新資料為準（修改後名稱、花費會更新）。
    let tag: Tag

    @State private var transactions: [MMCore.Transaction]?
    /// 沒拿到後端的資料時，說明現在顯示的是什麼。
    @State private var notice: String?
    @State private var editing: MMCore.Transaction?
    @State private var editingTag: Tag?
    @State private var offlineNotice = false

    private var current: Tag { model.tags.first { $0.id == tag.id } ?? tag }

    var body: some View {
        List {
            Section { BudgetRow(tag: current) }

            Section {
                if let transactions {
                    ForEach(transactions) { transaction in
                        Button {
                            // 修改、刪除需要連線（§4.1）。
                            if model.isOffline { offlineNotice = true } else { editing = transaction }
                        } label: {
                            TransactionRow(transaction: transaction, showDay: true).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if transactions.isEmpty {
                        Text("還沒有交易掛這個 tag").foregroundStyle(.secondary)
                    }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } header: {
                Text(transactions.map { "交易 \($0.count) 筆" } ?? "交易")
            } footer: {
                if let notice {
                    Text(notice).foregroundStyle(Palette.warning)
                }
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("修改") { editingTag = current }
            }
        }
        .task { await load() }
        .refreshable {
            await model.refreshLedgerData()
            await load()
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { transaction in
            QuickEntryView(editing: transaction)
        }
        .sheet(item: $editingTag) { tag in
            BudgetEditor(editing: tag)
        }
        .alert("需要連線", isPresented: $offlineNotice) {
            Button("好") {}
        } message: {
            Text("修改或刪除已上傳的交易需要連線。")
        }
        // tag 被刪掉了（修改畫面裡的「刪除」）：這一頁沒有東西可以看了。
        .onChange(of: model.tags) { _, tags in
            if !tags.contains(where: { $0.id == tag.id }) { dismiss() }
        }
    }

    private func load() async {
        guard let ledger = model.selectedLedger else { return }
        // 這個月已經載入的先顯示，避免空白；後端的結果回來再換掉。
        let loaded = model.transactions.filter { $0.tags.contains { $0.id == tag.id } }
        if transactions == nil { transactions = loaded }
        guard !model.isOffline else {
            notice = "離線中，只顯示這個月的交易。"
            return
        }
        do {
            let list = try await model.api.transactions(ledger: ledger.id, tag: tag.id)
            transactions = list.sorted { $0.transactionDate > $1.transactionDate }
            notice = nil
        } catch {
            transactions = loaded
            let reason = (error as? APIError)?.message ?? error.localizedDescription
            notice = "讀取失敗，只顯示這個月的交易。（\(reason)）"
        }
    }
}
