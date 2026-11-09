import MMCore
import SwiftUI

/// 交易列表（設計畫布「Transactions」）：依日期分組，每組顯示當天花費。
///
/// 這個月接下來會自動記的固定收支，以「預定」列顯示在它的日期裡（不算進花費），點了可以修改規則。
struct TransactionsView: View {
    @Environment(AppModel.self) private var model
    @State private var category: TransactionCategory?
    @State private var deleteError: String?
    @State private var editing: MMCore.Transaction?
    @State private var editingRule: RecurringRule?
    @State private var offlineNotice = false

    private struct DayGroup {
        let day: LocalDate
        let transactions: [MMCore.Transaction]
        let scheduled: [RecurringRule]
        let spent: Money
    }

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
                            ForEach(group.scheduled) { rule in
                                ScheduledRow(rule: rule)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingRule = rule }
                            }
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
                                if !group.transactions.isEmpty {
                                    Text("花費 \(group.spent.display)")
                                }
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
            .sheet(item: $editingRule) { rule in
                RecurringRuleEditor(editing: rule)
            }
            .alert("需要連線", isPresented: $offlineNotice) {
                Button("好") {}
            } message: {
                Text("修改或刪除已上傳的交易需要連線。")
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

    /// 這個月預定的固定收支（分類篩選也套用）。
    private var scheduled: [RecurringRule] {
        let rules = (model.recurringRules ?? []).scheduled(in: model.month, today: model.today)
        guard let category else { return rules }
        return rules.filter { $0.category == category }
    }

    private var days: [DayGroup] {
        let groups = Dictionary(grouping: filtered) { LocalDate($0.transactionDate, in: model.timeZone) }
        let scheduledGroups = Dictionary(grouping: scheduled, by: \.nextRunDate)
        return Set(groups.keys).union(scheduledGroups.keys).sorted(by: >).map { day in
            let list = groups[day] ?? []
            let spent = list.reduce(Money.zero) { total, transaction in
                let amount = transaction.amount ?? .zero
                return transaction.transactionType == .expense ? total + amount : total - amount
            }
            return DayGroup(day: day, transactions: list, scheduled: scheduledGroups[day] ?? [], spent: spent)
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
                HStack(spacing: 6) {
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    // tag 用色點，名稱太長會擠掉其他資訊；點進修改畫面或預算頁看得到名稱。
                    if !transaction.tags.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(transaction.tags) { TagDot(key: $0.colorKey) }
                        }
                        .accessibilityElement()
                        .accessibilityLabel(transaction.tags.map(\.name).joined(separator: "、"))
                    }
                }
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
        if transaction.recurringRule != nil { parts.append("固定收支") }
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

/// 預定會自動記帳的固定收支。還不是交易：不算進花費，到了那天由後端產生。
struct ScheduledRow: View {
    let rule: RecurringRule

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: rule.category).opacity(0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.description).foregroundStyle(.secondary)
                Label("預定・自動記帳", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountText)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var amountText: String {
        if let original = rule.originalAmount, let currency = rule.originalCurrency {
            return "\(currency) \(original.display)"
        }
        return (rule.amount ?? .zero).signed(for: rule.transactionType)
    }
}
