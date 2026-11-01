import MMCore
import SwiftUI

/// 首頁（設計畫布「Main」）：本月花費、四個記帳入口、預算、最近交易。
struct HomeView: View {
    @Environment(AppModel.self) private var model

    enum Entry: String, Identifiable {
        case form, voice, receipt, text
        var id: String { rawValue }
    }

    @State private var entry: Entry?
    @State private var showInbox = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfflineBanner()
                ScrollView {
                    VStack(spacing: 16) {
                        monthCard
                        entryButtons
                        if !model.monthBudgets.isEmpty { budgetsCard }
                        recentCard
                    }
                    .padding(16)
                }
                .refreshable { await model.syncNow() }
            }
            .background(Color(.secondarySystemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LedgerMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.inboxCount > 0 || !model.waitingItems.isEmpty {
                        Button { showInbox = true } label: {
                            Text("待處理 \(model.inboxCount + model.waitingItems.count)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Palette.accentSoft, in: Capsule())
                                .foregroundStyle(Palette.accentText)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showInbox) { InboxView() }
            .sheet(item: $entry) { entry in
                switch entry {
                case .form: QuickEntryView()
                case .voice: VoiceEntryView()
                case .receipt: ReceiptEntryView()
                case .text: TextEntryView()
                }
            }
        }
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonthMenu().font(.subheadline)
            Text(model.isCurrentMonth ? "本月花費" : "\(model.month.month) 月花費")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.monthSpent.display).font(.system(size: 40, weight: .bold, design: .rounded))
                Text(model.selectedLedger?.currency ?? "").foregroundStyle(.secondary)
            }
            if let change = model.monthChange {
                Text("較上月 \(change >= 0 ? "+" : "−")\(Int((abs(change) * 100).rounded()))%")
                    .font(.footnote)
                    .foregroundStyle(change > 0 ? Palette.warning : Palette.income)
            }
            if !model.pendingTransactions.isEmpty {
                // 本月花費只算已經上傳的，避免顯示後端沒有的數字（§4.5）。
                Text("不含 \(model.pendingTransactions.count) 筆尚未上傳")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var entryButtons: some View {
        HStack(spacing: 10) {
            entryButton("記一筆", "plus", .form, primary: true)
            entryButton("語音", "mic", .voice)
            entryButton("拍收據", "doc.viewfinder", .receipt)
            entryButton("文字", "text.bubble", .text)
        }
    }

    private func entryButton(_ title: String, _ symbol: String, _ entry: Entry, primary: Bool = false) -> some View {
        Button { self.entry = entry } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.footnote.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(primary ? .white : Palette.accentText)
            .background(primary ? Palette.accent : Palette.accentSoft, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var budgetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("預算").font(.headline)
                Spacer()
            }
            ForEach(model.monthBudgets.prefix(3)) { tag in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(tag.name).font(.subheadline)
                        Spacer()
                        Text("\(tag.spent.display) / \(tag.budgetAmount?.display ?? "")")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    BudgetBar(tag: tag)
                }
            }
        }
        .card()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近交易").font(.headline).padding(.bottom, 8)
            if model.transactions.isEmpty && model.pendingTransactions.isEmpty {
                Text(model.isLoading ? "載入中…" : "這個月還沒有交易")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
            ForEach(model.pendingTransactions.prefix(3)) { input in
                PendingRow(input: input)
                Divider()
            }
            ForEach(model.transactions.prefix(5)) { transaction in
                TransactionRow(transaction: transaction, showDay: true)
                Divider()
            }
        }
        .card()
    }
}
