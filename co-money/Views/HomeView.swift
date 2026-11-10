import MMCore
import SwiftUI

/// 首頁（設計畫布「Main」）：本月花費、三個記帳入口、預算、最近交易。
///
/// 只放每天要看、要用的東西。記帳入口只放「把剛剛那筆記下來」的方式（離線都能用）；打字在語音畫面裡。
/// 固定收支是很少動的設定，不放首頁：本月預定的出現在交易分頁，設定從交易的修改畫面或「我」進去。
struct HomeView: View {
    @Environment(AppModel.self) private var model

    @State private var entry: EntryKind?
    @State private var showInbox = false
    @State private var editing: MMCore.Transaction?
    @State private var offlineNotice = false

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
                }
            }
            .sheet(item: $editing) { transaction in
                QuickEntryView(editing: transaction)
            }
            .alert("需要連線", isPresented: $offlineNotice) {
                Button("好") {}
            } message: {
                Text("修改或刪除已上傳的交易需要連線。")
            }
            // 點了提醒通知（本身或上面的按鈕）：打開對應的記帳畫面。冷啟動時通知比首頁先到，所以出現時也要看一次。
            .onAppear(perform: openRequestedEntry)
            .onChange(of: model.pendingEntry) { _, _ in openRequestedEntry() }
        }
    }

    private func openRequestedEntry() {
        guard let requested = model.pendingEntry else { return }
        model.pendingEntry = nil
        editing = nil
        entry = requested
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
            ForEach(EntryKind.allCases) { kind in
                entryButton(kind, primary: kind == .form)
            }
        }
    }

    private func entryButton(_ kind: EntryKind, primary: Bool) -> some View {
        Button { entry = kind } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.symbol).font(.title3)
                Text(kind.title).font(.footnote.weight(.medium))
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
            // 點一個預算看掛在上面的交易。
            ForEach(model.monthBudgets.prefix(3)) { tag in
                NavigationLink { TagDetailView(tag: tag) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            TagDot(key: tag.colorKey)
                            Text(tag.name).font(.subheadline)
                            Spacer()
                            Text("\(tag.spent.display) / \(tag.budgetAmount?.display ?? "")")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        BudgetBar(tag: tag)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                Button {
                    // 修改、刪除需要連線（§4.1）。
                    if model.isOffline { offlineNotice = true } else { editing = transaction }
                } label: {
                    TransactionRow(transaction: transaction, showDay: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .card()
    }
}
