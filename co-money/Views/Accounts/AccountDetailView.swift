// AccountDetailView.swift
// co-money

import SwiftUI

/// AccountDetailView: 帳戶詳情檢視
/// AccountDetailView displays transaction summary and list for a specific account.
/// Supports three modes:
/// 1. Total view (accountId = nil): All transactions across all accounts
/// 2. Personal view (accountId = "personal"): User's personal transactions from /api/transactions/mine/
/// 3. Shared account (accountId = UUID): Specific shared account transactions
struct AccountDetailView: View {
    let cardTitle:  String
    let accountId:  String?          // nil=total, "personal"=personal, UUID=shared account
    let account:    SharedAccount?   // non-nil when accountId is a UUID

    // MARK: - Environment: Injected view models from parent
    @Environment(TransactionViewModel.self) private var txVM
    @Environment(AccountViewModel.self)     private var accountVM
    @Environment(ProfileViewModel.self)     private var profileVM

    // MARK: - State: Transaction filtering & pagination
    @State private var filtered:         [Transaction] = []
    @State private var currentMonth:     String?
    @State private var previousMonthUrl: String?
    @State private var nextMonthUrl:     String?
    @State private var isLoading         = false
    @State private var errorMessage:     String?

    // MARK: - Sheet State: Invitation management
    @State private var showInvite  = false

    // MARK: - Computed Properties
    /// Pagination helpers: Check if navigation buttons should be enabled
    private var hasPrevious: Bool { previousMonthUrl != nil }
    private var hasNext:     Bool { nextMonthUrl != nil }

    /// Summary helper: Get transaction summary (income, expense, balance) from ViewModel
    private var summary:     TransactionSummary { txVM.summary(forAccountId: accountId) }

    var body: some View {
        VStack(spacing: 0) {

            // ─── OVERVIEW: income / expense / balance ─────────────────
            // 顯示收入、支出、結餘的摘要卡片 (Shows income, expense, and balance summary)
            SummaryHeaderCard(summary: summary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color(.secondarySystemBackground))

            // ─── MONTH NAVIGATION ─────────────────────────────────────
            // 允許使用者在月份之間瀏覽交易 (Allows user to navigate between months)
            MonthNavigationBar(
                currentMonth: currentMonth,
                hasPrevious:  hasPrevious,
                hasNext:      hasNext,
                onPrevious:   { Task { await navigatePrevious() } },
                onNext:       { Task { await navigateNext() } }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            Divider()

            // ─── TRANSACTION LIST ──────────────────────────────────────
            // 顯示該月份的交易列表，支援下滑刪除 (Shows transaction list, supports swipe-to-delete)
            if isLoading && filtered.isEmpty {
                Spacer()
                ProgressView("載入中...")
                Spacer()
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    "本月尚無記帳",
                    systemImage: "tray",
                    description: Text("透過右下角 + 新增記帳")
                )
            } else {
                List {
                    ForEach(filtered) { tx in
                        // MARK: Navigation Link: 點擊進入交易詳情 (Tap to enter transaction detail)
                        NavigationLink {
                            TransactionDetailView(transaction: tx)
                                .environment(txVM)
                                .environment(accountVM)
                                .environment(profileVM)
                        } label: {
                            TransactionRowView(transaction: tx)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete { indices in
                        // MARK: Delete Action: 下滑刪除交易 (Swipe to delete transaction)
                        for i in indices {
                            let id = filtered[i].id
                            Task {
                                await txVM.deleteTransaction(id: id)
                                filtered.removeAll { $0.id == id }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                // MARK: Pull-to-Refresh: 下拉重新載入 (Pull down to refresh)
                .refreshable { await loadFromVM() }
            }
        }
        .navigationTitle(cardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        // MARK: Initial Load: 檢視載入時獲取數據 (Fetch data when view loads)
        .task { await loadFromVM() }
        .toolbar {
            // MARK: Invite Button: 僅限共享帳戶使用 (Invite button only for shared accounts)
            if account != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showInvite = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
        }
        // MARK: Invitation Sheet: Modal for sending invitations
        .sheet(isPresented: $showInvite) {
            if let acc = account {
                SendInvitationSheet(
                    accounts:             accountVM.accounts,
                    preselectedAccountId: acc.id,
                    isPresented:          $showInvite
                ) { accId, username in
                    Task {
                        _ = try? await AccountService.shared.inviteMember(
                            accountId:       accId,
                            inviteeUsername: username
                        )
                    }
                }
                .environment(accountVM)
            }
        }
        // MARK: Error Alert: 顯示錯誤訊息 (Show error messages)
        .alert("錯誤", isPresented: .constant(errorMessage != nil)) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Data helpers

    /// Check if this is personal account view
    private var isPersonal: Bool { accountId == "personal" }

    /// Specific shared-account ID (not nil, not "personal"). Used to route
    /// requests to /accounts/{id}/transactions/ for authoritative per-account
    /// data.
    /// 特定共用帳戶的 ID（非 nil、非 personal），用於走 /accounts/{id}/transactions/
    /// 取得各帳戶權威資料。
    private var sharedAccountId: String? {
        guard let id = accountId, id != "personal" else { return nil }
        return id
    }

    /// Load data from the right endpoint based on account type:
    /// - personal     → /transactions/mine/  (txVM.personalTransactions)
    /// - shared (UUID) → /accounts/{id}/transactions/  (txVM.accountStates[id])
    /// - total (nil)  → /transactions/  (txVM.transactions, already aggregated)
    /// 依帳戶類型走對應端點，避免從共用 transactions 做 client-side filter
    /// 而與後端權威資料失準。
    private func loadFromVM() async {
        if isPersonal {
            if txVM.personalTransactions.isEmpty
                || txVM.personalCurrentMonth != txVM.currentMonth {
                isLoading = true
                await txVM.loadPersonal(month: txVM.currentMonth)
                isLoading = false
            }
            currentMonth     = txVM.personalCurrentMonth
            previousMonthUrl = txVM.personalPreviousMonthUrl
            nextMonthUrl     = txVM.personalNextMonthUrl
            filtered         = txVM.personalTransactions
        } else if let id = sharedAccountId {
            // Per-account authoritative endpoint
            let state = txVM.accountStates[id]
            if state == nil || state?.currentMonth != txVM.currentMonth {
                isLoading = true
                await txVM.loadAccountTransactions(accountId: id, month: txVM.currentMonth)
                isLoading = false
            }
            let s = txVM.accountStates[id]
            currentMonth     = s?.currentMonth
            previousMonthUrl = s?.previousMonthUrl
            nextMonthUrl     = s?.nextMonthUrl
            filtered         = s?.transactions ?? []
        } else {
            // Total view (accountId == nil) — uses aggregated /transactions/
            currentMonth     = txVM.currentMonth
            previousMonthUrl = txVM.previousMonthUrl
            nextMonthUrl     = txVM.nextMonthUrl
            filtered         = txVM.transactions
        }
    }

    /// Navigate to previous month
    /// 導航到上一個月 (Navigate to previous month)
    private func navigatePrevious() async {
        guard let url = previousMonthUrl else { return }
        isLoading = true
        if isPersonal {
            await txVM.loadPersonalMonth(fullURL: url)
        } else if let id = sharedAccountId {
            await txVM.loadAccountTransactionsMonth(accountId: id, fullURL: url)
        } else {
            await txVM.loadTransactions(fullURL: url)
        }
        await loadFromVM()
        isLoading = false
    }

    /// Navigate to next month
    /// 導航到下一個月 (Navigate to next month)
    private func navigateNext() async {
        guard let url = nextMonthUrl else { return }
        isLoading = true
        if isPersonal {
            await txVM.loadPersonalMonth(fullURL: url)
        } else if let id = sharedAccountId {
            await txVM.loadAccountTransactionsMonth(accountId: id, fullURL: url)
        } else {
            await txVM.loadTransactions(fullURL: url)
        }
        await loadFromVM()
        isLoading = false
    }
}

// MARK: - Currency Total (for per-currency display)
/// 儲存單一貨幣的金額 (Store amount for a single currency)
struct CurrencyTotal {
    let currency: String
    let amount:   Double
}

// MARK: - Category Breakdown Item (shared model used in HomeView + here)
/// 分類明細項目，用於支出分類圖表 (Category breakdown item for expense chart)
struct CategoryBreakdownItem: Identifiable {
    let id:          String
    let name:        String
    let icon:        String?           // emoji or nil
    let total:       Double            // sum across all currencies (for sorting/ratio)
    var perCurrency: [CurrencyTotal]   // per-currency amounts, sorted by amount desc
}

// MARK: - Category Breakdown Card
/// 顯示在 HomeView 概覽面板中的分類明細卡片
/// Shown on HomeView in the overview panel for the selected account card.
struct CategoryBreakdownCard: View {
    let items:   [CategoryBreakdownItem]
    let summary: TransactionSummary       // for per-currency totals in header

    // MARK: Color Palette: 用於不同分類的顏色 (Colors for different categories)
    private let palette: [Color] = [.orange, .blue, .purple, .pink, .teal]

    /// Grand total across all items (for ratio calculation)
    /// 所有項目的總和，用於比例計算 (Grand total for ratio)
    private var grandTotal: Double { items.reduce(0) { $0 + $1.total } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: Header: 顯示分類標題和貨幣總計 (Show category title and currency totals)
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("支出分類")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                // Show per-currency expense totals
                // 顯示每種貨幣的支出合計 (Show expense totals per currency)
                VStack(alignment: .trailing, spacing: 1) {
                    ForEach(summary.currencies.filter { $0.expense > 0 }) { cur in
                        Text(cur.expenseText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Category Rows: 每個分類一行，包含比例條 (Each category row with proportion bar)
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                let barColor = palette[idx % palette.count]
                let ratio    = grandTotal > 0 ? min(item.total / grandTotal, 1.0) : 0

                HStack(spacing: 10) {
                    // MARK: Icon Badge: 分類圖示或首字母 (Category icon or first letter)
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(barColor.opacity(0.15))
                            .frame(width: 28, height: 28)
                        if let icon = item.icon, !icon.isEmpty {
                            Text(icon).font(.system(size: 13))
                        } else {
                            Text(String(item.name.prefix(1)))
                                .font(.caption.bold())
                                .foregroundStyle(barColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            // MARK: Per-Currency Amounts: 按貨幣分別顯示金額 (Show amounts by currency)
                            VStack(alignment: .trailing, spacing: 1) {
                                ForEach(item.perCurrency, id: \.currency) { ct in
                                    Text(AmountFormatter.format(ct.amount, currency: item.perCurrency.count > 1 ? ct.currency : nil))
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundStyle(.primary)
                                }
                            }
                            Text(String(format: "%.0f%%", ratio * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }

                        // MARK: Proportion Bar: 視覺化分類的相對比例 (Visual proportion bar)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(barColor.opacity(0.75))
                                    .frame(width: geo.size.width * CGFloat(ratio), height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - Summary Header Card (multi-currency)
/// 顯示交易摘要（收入、支出、結餘）的卡片，支援多幣種
/// Shows transaction summary with support for multiple currencies
struct SummaryHeaderCard: View {
    let summary: TransactionSummary

    var body: some View {
        VStack(spacing: 0) {
            if summary.currencies.isEmpty {
                // MARK: Empty State: 沒有交易時顯示零值 (Show zeros when no transactions)
                SummaryRow(
                    incomeText: "0", expenseText: "0", balanceText: "0",
                    balancePositive: true, currency: nil
                )
            } else if !summary.isMultiCurrency {
                // MARK: Single Currency: 緊湊佈局，無需顯示貨幣標籤 (Compact layout without currency label)
                SummaryRow(
                    incomeText:  summary.incomeText,
                    expenseText: summary.expenseText,
                    balanceText: summary.balanceText,
                    balancePositive: summary.balance >= 0,
                    currency: nil
                )
            } else {
                // MARK: Multi-Currency: 每個貨幣一行，用分隔線分開 (One row per currency with dividers)
                ForEach(Array(summary.currencies.enumerated()), id: \.element.id) { idx, cur in
                    if idx > 0 {
                        Divider().padding(.horizontal, 12)
                    }
                    SummaryRow(
                        incomeText:  AmountFormatter.format(cur.income),
                        expenseText: AmountFormatter.format(cur.expense),
                        balanceText: AmountFormatter.format(abs(cur.balance)),
                        balancePositive: cur.balance >= 0,
                        currency: cur.currency
                    )
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
    }
}

// MARK: - Summary Row (one currency)
/// 單一貨幣的摘要列，顯示收入、支出、結餘
/// Summary row for one currency showing income, expense, balance
private struct SummaryRow: View {
    let incomeText:      String
    let expenseText:     String
    let balanceText:     String
    let balancePositive: Bool
    let currency:        String?     // shown as a left label when multi-currency

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Currency Label: 多幣種時顯示貨幣代碼 (Show currency code when multi-currency)
            if let cur = currency {
                Text(cur)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                    .padding(.leading, 10)
            }
            SummaryItem(label: "收入", value: incomeText,  color: .green)
            Divider().frame(height: 30)
            SummaryItem(label: "支出", value: expenseText, color: .red)
            Divider().frame(height: 30)
            SummaryItem(
                label: "結餘", value: balanceText,
                color: balancePositive ? Color.accentColor : .orange
            )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Summary Item
/// 摘要項目（單一指標如收入、支出、結餘）
/// Summary item component (single metric like income, expense, balance)
struct SummaryItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
