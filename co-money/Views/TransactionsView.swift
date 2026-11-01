import MMCore
import SwiftUI

/// 交易列表（設計畫布「Transactions」）：依日期分組，每組顯示當天花費。
struct TransactionsView: View {
    @Environment(AppModel.self) private var model
    @State private var category: TransactionCategory?
    @State private var deleteError: String?
    @State private var editing: MMCore.Transaction?
    @State private var offlineNotice = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfflineBanner()
                List {
                    if !model.pendingTransactions.isEmpty {
                        Section("等待上傳") {
                            ForEach(model.pendingTransactions) { PendingRow(input: $0) }
                        }
                    }
                    ForEach(days, id: \.day) { group in
                        Section {
                            ForEach(group.transactions) { transaction in
                                TransactionRow(transaction: transaction, showDay: false)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // 修改需要連線（§4.1）。
                                        if model.isOffline { offlineNotice = true } else { editing = transaction }
                                    }
                                    .swipeActions(allowsFullSwipe: false) {  // 刪除不能一滑到底就執行
                                        // 修改、刪除需要連線（§4.1）。
                                        Button("刪除", role: .destructive) {
                                            Task { await delete(transaction) }
                                        }
                                        .disabled(model.isOffline)
                                    }
                            }
                        } header: {
                            HStack {
                                Text(DateText.dayHeader(group.day, today: model.today))
                                Spacer()
                                Text("花費 \(group.spent.display)")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await model.refreshLedgerData() }
            }
            .navigationTitle("交易")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MonthMenu() }
                ToolbarItem(placement: .topBarTrailing) { categoryMenu }
            }
            .sheet(item: $editing) { transaction in
                QuickEntryView(editing: transaction)
            }
            .alert("需要連線", isPresented: $offlineNotice) {
                Button("好") {}
            } message: {
                Text("修改已上傳的交易需要連線。")
            }
            .alert("刪除失敗", isPresented: .constant(deleteError != nil)) {
                Button("好") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private var filtered: [MMCore.Transaction] {
        guard let category else { return model.transactions }
        return model.transactions.filter { $0.category == category }
    }

    private var days: [(day: LocalDate, transactions: [MMCore.Transaction], spent: Money)] {
        let groups = Dictionary(grouping: filtered) { LocalDate($0.transactionDate, in: model.timeZone) }
        return groups.keys.sorted(by: >).map { day in
            let list = groups[day]!
            let spent = list.reduce(Money.zero) { total, transaction in
                let amount = transaction.amount ?? .zero
                return transaction.transactionType == .expense ? total + amount : total - amount
            }
            return (day, list, spent)
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button("全部") { category = nil }
            ForEach(TransactionCategory.allCases) { item in
                Button(item.label) { category = item }
            }
        } label: {
            Text(category?.label ?? "分類")
        }
    }

    private func delete(_ transaction: MMCore.Transaction) async {
        do {
            try await model.delete(transaction)
        } catch let error as APIError {
            deleteError = error.message
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

struct TransactionRow: View {
    @Environment(AppModel.self) private var model
    let transaction: MMCore.Transaction
    var showDay: Bool

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description).font(.body)
                Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((transaction.amount ?? .zero).signed(for: transaction.transactionType))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(transaction.transactionType == .income ? Palette.income : .primary)
                if let original = transaction.originalAmount, let currency = transaction.originalCurrency {
                    Text("\(currency) \(original.display)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var meta: String {
        var parts: [String] = []
        if showDay {
            parts.append(DateText.shortDay(LocalDate(transaction.transactionDate, in: model.timeZone), today: model.today))
        }
        parts.append(transaction.payer.username)
        if transaction.transactionType == .income { parts.append("收入") }
        parts += transaction.tags.map(\.name)
        if transaction.recurringRule != nil { parts.append("重複交易") }
        return parts.joined(separator: "・")
    }
}

/// 還沒上傳的交易。
struct PendingRow: View {
    let input: TransactionInput

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: input.category).opacity(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(input.description)
                Label("等待上傳", systemImage: "icloud.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let shown = input.displayAmount {
                Text([shown.1, shown.0.signed(for: input.transactionType)].compactMap { $0 }.joined(separator: " "))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
