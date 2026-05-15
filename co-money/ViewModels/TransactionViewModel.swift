// TransactionViewModel.swift
// co-money

import Foundation

/// MARK: - CurrencyAmount Struct
///
/// Represents income, expense, and balance for a single currency
/// Used in multi-currency transaction summaries
/// 代表单个货币的收入、支出和余额
/// 用于多货币交易摘要
///
/// Example (示例):
/// CurrencyAmount(currency: "USD", income: 5000, expense: 2000)
/// balance = 3000, spendRatio = 0.4 (spent 40% of income)
struct CurrencyAmount: Identifiable {
    var id: String { currency }  // Required by Identifiable protocol (由 Identifiable 协议要求)

    /// ISO currency code (ISO 货币代码) - e.g., "USD", "TWD", "EUR"
    let currency: String

    /// Total income for this currency in this time period
    /// 本期间此货币的总收入
    let income:  Double

    /// Total expense for this currency in this time period
    /// 本期间此货币的总支出
    let expense: Double

    /// Computed balance: income minus expenses
    /// 计算余额: 收入减去支出
    var balance: Double { income - expense }

    /// Formatted income text with currency symbol
    /// 格式化的带有货币符号的收入文本
    var incomeText:  String { AmountFormatter.format(income, currency: currency) }

    /// Formatted expense text with currency symbol
    /// 格式化的带有货币符号的支出文本
    var expenseText: String { AmountFormatter.format(expense, currency: currency) }

    /// Formatted balance text (always absolute value to avoid -$ appearance)
    /// 格式化的余额文本（始终为绝对值以避免 -$ 外观）
    var balanceText: String { AmountFormatter.format(abs(balance), currency: currency) }

    /// Spend ratio: what fraction of income was spent (0.0 to 1.0)
    /// 支出比率: 收入的哪个部分被花费（0.0 到 1.0）
    ///
    /// Calculation (计算):
    /// - If no income and no expenses: 0 (healthy - no activity)
    /// - If no income but has expenses: 1 (overspent - 超支)
    /// - Otherwise: expense / income, capped at 1.0
    /// - If ratio > 1.0 (spent more than earned), still show as 1.0 (100%)
    var spendRatio: Double {
        guard income > 0 else { return expense > 0 ? 1 : 0 }
        return min(expense / income, 1)
    }

    /// Volume = total activity: income + expense
    /// Used for sorting by "most active" currency first
    /// 体积 = 总活动: 收入 + 支出
    /// 用于先按"最活跃"的货币排序
    var volume: Double { income + expense }
}

/// MARK: - TransactionSummary Struct
///
/// Aggregated transaction data across multiple currencies
/// Provides both detailed per-currency breakdown and convenient primary currency access
/// 跨多种货币的聚合交易数据
/// 提供详细的按货币分解和方便的主要货币访问
///
/// Purpose (目的):
/// Views display this to show total income/expenses/balance. The ViewModel computes it
/// from the transaction list (client-side filtering and aggregation).
/// 视图显示这个以显示总收入/支出/余额。ViewModel 从交易列表计算它
/// （客户端过滤和聚合）。
struct TransactionSummary {
    /// MARK: - Core Data (核心数据)

    /// Per-currency breakdown sorted by volume (most active first)
    /// 按体积排序的按货币分解（最活跃的优先）
    let currencies: [CurrencyAmount]

    /// MARK: - Derived Properties (派生属性)

    /// Primary (dominant) currency — the one with the most activity
    /// If no currencies, return a default empty "TWD" (台湾默认货币)
    /// 主要（主导）货币 — 活动最多的
    /// 如果没有货币，返回默认的空"TWD"
    var primary: CurrencyAmount {
        currencies.first ?? CurrencyAmount(currency: "TWD", income: 0, expense: 0)
    }

    /// Is this a multi-currency transaction summary? (True if 2+ currencies)
    /// 这是多货币交易摘要吗？（如果 2+ 种货币则为 True）
    var isMultiCurrency: Bool { currencies.count > 1 }

    // ── Convenience accessors (primary currency) (便利访问器 (主要货币)) ────────────────────
    // These properties allow Views to simply call summary.income instead of summary.primary.income
    // 这些属性允许 Views 简单地调用 summary.income 而不是 summary.primary.income

    /// Primary currency income
    /// 主要货币收入
    var income:  Double { primary.income }

    /// Primary currency expense
    /// 主要货币支出
    var expense: Double { primary.expense }

    /// Primary currency balance (income - expense)
    /// 主要货币余额（收入 - 支出）
    var balance: Double { primary.balance }

    /// Formatted income text for primary currency
    /// 主要货币的格式化收入文本
    var incomeText:  String { primary.incomeText }

    /// Formatted expense text for primary currency
    /// 主要货币的格式化支出文本
    var expenseText: String { primary.expenseText }

    /// Formatted balance text for primary currency
    /// 主要货币的格式化余额文本
    var balanceText: String { primary.balanceText }

    /// Spend ratio for primary currency (0.0 = not spent, 1.0 = all spent)
    /// 主要货币的支出比率（0.0 = 未花费，1.0 = 全部花费）
    var spendRatio: Double { primary.spendRatio }
}

/// MARK: - TransactionViewModel Overview (交易视图模型概述)
///
/// TransactionViewModel manages transaction data fetching, caching, and client-side computation.
/// This is the business logic layer between Views and Transaction APIs.
/// 交易视图模型管理交易数据获取、缓存和客户端计算。
/// 这是 Views 和 Transaction APIs 之间的业务逻辑层。
///
/// ┌─────────────────────────────────────────────────────────────┐
/// │  MVVM Data Flow for Transactions (交易数据流):               │
/// │                                                               │
/// │  1. View calls loadFromCache()                              │
/// │     视图调用 loadFromCache()                                 │
/// │     ↓ (Instant, offline - 即时，离线)                       │
/// │  2. TransactionViewModel loads from disk cache              │
/// │     交易视图模型从磁盘缓存加载                               │
/// │     → transactions, personalTransactions, categories       │
/// │                                                               │
/// │  3. View calls loadAll() (async network fetch)              │
/// │     视图调用 loadAll()（异步网络获取）                      │
/// │     ↓ (Main thread doesn't block)                           │
/// │  4. Service makes API requests                              │
/// │     服务进行 API 请求                                        │
/// │     /api/transactions/  and  /api/categories/              │
/// │     ↓                                                         │
/// │  5. Service parses JSON response                            │
/// │     服务解析 JSON 响应                                       │
/// │     ↓                                                         │
/// │  6. ViewModel updates @Observable properties                │
/// │     ViewModel 更新 @Observable 属性                          │
/// │     → SwiftUI detects changes and re-renders                │
/// │     → SwiftUI 检测到变化并重新渲染                           │
/// │  7. ViewModel saves to cache (write-through)                │
/// │     ViewModel 保存到缓存（写穿）                             │
/// │     For offline support and faster launches                 │
/// │     用于离线支持和更快的启动                                 │
/// └─────────────────────────────────────────────────────────────┘
///
/// Key Patterns (关键模式):
/// 1. Cache-first loading: Instant UI with local cache, then update from network
///    缓存优先加载: 使用本地缓存即时 UI，然后从网络更新
/// 2. Pagination: previousMonthUrl/nextMonthUrl for navigating months
///    分页: previousMonthUrl/nextMonthUrl 用于导航月份
/// 3. Multi-currency support: summarize() groups amounts by currency
///    多货币支持: summarize() 按货币分组金额
/// 4. Category breakdown: categoryBreakdown() slices expenses by category
///    类别分解: categoryBreakdown() 按类别切割支出
/// 5. AI-powered parsing: parseOnly() sends receipts/voice to backend for OCR/NLP
///    人工智能解析: parseOnly() 将收据/语音发送到后端进行 OCR/NLP
///
@Observable
final class TransactionViewModel {
    /// MARK: - Shared Account Transactions (共享账户交易)
    /// Data from /api/transactions/ (publicly shared transactions across accounts)
    /// 来自 /api/transactions/ 的数据（跨账户的公开共享交易）

    /// List of shared account transactions (shared with team)
    /// 共享账户交易列表（与团队共享）
    var transactions:     [Transaction] = []

    /// Categories available for categorizing transactions
    /// 用于分类交易的可用类别
    var categories:       [Category]    = []

    /// Current month string in format "2024-01" for display
    /// 当前月份字符串，格式为"2024-01"用于显示
    var currentMonth:     String?

    /// Pagination: URL to fetch previous month's transactions
    /// 分页: 用于获取上个月交易的 URL
    var previousMonthUrl: String?

    /// Pagination: URL to fetch next month's transactions
    /// 分页: 用于获取下个月交易的 URL
    var nextMonthUrl:     String?

    /// Convenience properties: check if navigation is possible
    /// 便利属性: 检查是否可以导航
    var hasPreviousMonth: Bool { previousMonthUrl != nil }
    var hasNextMonth:     Bool { nextMonthUrl != nil }

    /// MARK: - Personal Transactions (个人交易)
    /// Data from /api/transactions/mine/ (user's personal transactions, not shared)
    /// 来自 /api/transactions/mine/ 的数据（用户的个人交易，未共享）

    /// List of personal transactions (only for this user)
    /// 个人交易列表（仅供该用户）
    var personalTransactions:     [Transaction] = []

    /// Current month for personal transactions
    /// 个人交易的当前月份
    var personalCurrentMonth:     String?

    /// Pagination for personal transactions
    /// 个人交易的分页
    var personalPreviousMonthUrl: String?
    var personalNextMonthUrl:     String?

    /// MARK: - Per-Shared-Account Transactions (各共用帳戶交易)
    ///
    /// Each shared account has its own authoritative endpoint
    /// `/accounts/{id}/transactions/`. We store the response per account here
    /// instead of filtering the global `transactions` list client-side, because
    /// other users can modify their accounts and the global aggregation may not
    /// reflect those changes in time.
    /// 每個共用帳戶有自己的權威端點 `/accounts/{id}/transactions/`，這裡按帳戶
    /// ID 個別儲存，避免從全域 `transactions` 客戶端再篩選導致與他人修改不同步。
    struct AccountState {
        var transactions:     [Transaction] = []
        var currentMonth:     String?
        var previousMonthUrl: String?
        var nextMonthUrl:     String?
    }

    /// Per-account state keyed by account ID.
    /// 以 account ID 為鍵的各帳戶狀態。
    var accountStates: [String: AccountState] = [:]

    /// MARK: - Loading State (加载状态)

    /// isLoading: Shows loading spinner while fetching from API
    /// isLoading: 从 API 获取时显示加载动画
    var isLoading    = false

    /// Prevents repeated month taps from launching duplicate requests for the same stale URL.
    /// 防止切月時連點送出多個舊 URL request。
    var isChangingMonth = false

    /// errorMessage: Stores the last error message from API calls
    /// errorMessage: 存储来自 API 调用的最后一条错误消息
    var errorMessage: String?

    /// MARK: - Dependencies (依赖项)

    /// Transaction API service (handles network requests)
    /// 交易 API 服务（处理网络请求）
    private let txService  = TransactionService.shared

    /// Category API service
    /// 类别 API 服务
    private let catService = CategoryService.shared

    // MARK: - Load from Server

    /// Load both shared transactions and categories from API
    /// Combines two async requests for efficiency
    /// 从 API 加载共享交易和类别
    /// 结合两个异步请求以提高效率
    ///
    /// Pattern: async let (并发执行 - Concurrent Execution)
    /// Both API requests run in parallel (not sequential)
    /// 两个 API 请求并行运行（非顺序）
    ///
    /// Execution Flow (执行流程):
    /// 1. Set isLoading = true (show spinner)
    ///    设置 isLoading = true（显示加载动画）
    /// 2. Start both API requests concurrently
    ///    并发启动两个 API 请求
    /// 3. Wait for BOTH to complete (faster than sequential)
    ///    等待两者都完成（比顺序更快）
    /// 4. Parse paginated response and extract pagination URLs
    ///    解析分页响应并提取分页 URL
    /// 5. Save all data to cache for offline support
    ///    将所有数据保存到缓存以支持离线
    /// 6. Set isLoading = false (hide spinner)
    ///    设置 isLoading = false（隐藏加载动画）
    func loadAll() async {
        isLoading    = true
        errorMessage = nil

        /// Set currentMonth to today BEFORE the API call so the UI shows the correct
        /// month immediately — not after the response arrives.
        /// The backend's current_month field reflects the latest transaction date in the DB,
        /// not the ?month= param, so we never use it for the initial load.
        /// 在打 API 之前就設好 currentMonth，讓 UI 立即顯示正確月份，不需要等 API 回應。
        /// 後端的 current_month 是依 DB 最新交易決定的，不是依 ?month= 參數，所以初始載入不採用它。
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        currentMonth = formatter.string(from: Date())
        print("[loadAll] currentMonth set to \(currentMonth!) before API call")

        /// async let: Start both requests in parallel, don't wait yet
        /// async let: 并行启动两个请求，先不等待
        async let txResult  = txService.getTransactions()
        async let catResult = catService.getCategories()

        do {
            let (txList, cats) = try await (txResult, catResult)
            print("[loadAll] ── response ──────────────────────────────")
            print("[loadAll]   current_month : \(txList.currentMonth ?? "nil")")
            print("[loadAll]   count         : \(txList.count ?? 0)")
            print("[loadAll]   results       : \(txList.results.count) transactions")
            print("[loadAll]   previousUrl   : \(txList.previousMonthUrl ?? "nil")")
            print("[loadAll]   nextUrl       : \(txList.nextMonthUrl ?? "nil")")
            for tx in txList.results {
                print("[loadAll]     tx: \(tx.id) | \(tx.transactionDate) | \(tx.amount) | \(tx.description)")
            }
            print("[loadAll] ────────────────────────────────────────────")

            /// Apply only transactions and pagination URLs; ignore backend's currentMonth
            /// 只套用交易資料與分頁 URL，不採用後端的 currentMonth
            transactions     = txList.results
            previousMonthUrl = txList.previousMonthUrl
            nextMonthUrl     = txList.nextMonthUrl

            /// Backfill pagination URLs if the API didn't return them, so the
            /// previous/next month buttons remain usable.
            /// 若 API 沒有回傳分頁 URL，從目前月份自行建立，讓上一月/下一月按鈕可用。
            if previousMonthUrl == nil || nextMonthUrl == nil, let m = currentMonth {
                let urls = buildSharedMonthURLs(from: m)
                if previousMonthUrl == nil { previousMonthUrl = urls.previous }
                if nextMonthUrl     == nil { nextMonthUrl     = urls.next }
            }

            /// Update categories
            categories = cats


        } catch {
            /// Network or parsing error
            /// 网络或解析错误
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Load personal (non-shared) transactions for current user
    /// 加载当前用户的个人（非共享）交易
    ///
    /// Differences from loadAll() (与 loadAll() 的区别):
    /// - Fetches from /api/transactions/mine/ (personal only)
    ///   从 /api/transactions/mine/ 获取（仅限个人）
    /// - Non-fatal errors (personal section can be empty)
    ///   非致命错误（个人部分可以为空）
    /// - Runs silently without updating errorMessage
    ///   静默运行而不更新 errorMessage
    func loadPersonal(month: String? = nil) async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        /// Single source of truth for the active month is `currentMonth`. When no
        /// explicit month is passed, fall back to `currentMonth` first (the month
        /// the user is currently viewing) and only fall back to today as a last
        /// resort. Both `currentMonth` and `personalCurrentMonth` are updated so
        /// every consumer reading either field sees the same active month.
        /// 月份單一真相來源是 currentMonth：未指定 month 時優先用 currentMonth，
        /// 最後才退回今天；同時更新 currentMonth 與 personalCurrentMonth，避免
        /// 任一邊讀到舊的月份。
        let effectiveMonth = month ?? currentMonth ?? formatter.string(from: Date())
        personalCurrentMonth = effectiveMonth
        currentMonth         = effectiveMonth
        print("[loadPersonal] personalCurrentMonth/currentMonth set to \(effectiveMonth) before API call")

        do {
            let list = try await txService.getMyTransactions(month: effectiveMonth)
            print("[loadPersonal] ── response ──────────────────────────")
            print("[loadPersonal]   current_month : \(list.currentMonth ?? "nil")")
            print("[loadPersonal]   count         : \(list.count ?? 0)")
            print("[loadPersonal]   results       : \(list.results.count) transactions")
            print("[loadPersonal]   previousUrl   : \(list.previousMonthUrl ?? "nil")")
            print("[loadPersonal]   nextUrl       : \(list.nextMonthUrl ?? "nil")")
            for tx in list.results {
                print("[loadPersonal]     tx: \(tx.id) | \(tx.transactionDate) | \(tx.amount) | \(tx.description)")
            }
            print("[loadPersonal] ──────────────────────────────────────")

            /// Route through applyPersonalPage so every consumer of `currentMonth`
            /// / `personalCurrentMonth` is updated by exactly one code path,
            /// using `effectiveMonth` as the fallback when the backend omits it.
            /// 統一走 applyPersonalPage：所有寫月份狀態的邏輯集中在一處，並以
            /// effectiveMonth 作為後端未回傳時的備援。
            applyPersonalPage(list, fallbackMonth: effectiveMonth)


        } catch {
            /// Non-fatal: personal section may simply be empty for this user
            /// 非致命: 个人部分对此用户可能只是空的
            // Silently ignore - don't set errorMessage
            // 静默忽略 - 不设置 errorMessage
        }
    }

    /// Load a specific month of personal transactions using pagination URL
    /// 使用分页 URL 加载特定月份的个人交易
    ///
    /// Parameter: fullURL - Complete URL from personalPreviousMonthUrl or personalNextMonthUrl
    /// 参数: fullURL - 来自 personalPreviousMonthUrl 或 personalNextMonthUrl 的完整 URL
    func loadPersonalMonth(fullURL: String) async {
        do {
            /// Fetch using provided URL (returned from previous response)
            /// 使用提供的 URL 获取（从先前的响应返回）
            let oldMonth = currentMonth
            let list = try await txService.getMyTransactions(fullURL: fullURL)
            applyPersonalPage(list, fallbackMonth: Self.extractMonth(from: fullURL))

            /// Personal navigation just changed the master `currentMonth`. The
            /// shared `transactions` list is now stale for the new month, so
            /// refresh it too — otherwise other views (HomeView total/shared
            /// cards, TransactionListView) would show the previous month's data.
            /// 個人切月後，共用 transactions 已過期，必須同步刷新，否則回到首頁
            /// 或交易列表時會看到舊月份資料。
            if let m = currentMonth, m != oldMonth {
                await refreshSharedForCurrentMonth()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch the shared transactions endpoint for the current `currentMonth`
    /// without cascading back into personal (which has already been refreshed
    /// by the caller). Used when a personal-only navigation changes the master
    /// month and we need to bring shared data into alignment.
    /// 為目前 currentMonth 重打共用交易 endpoint，且不再回頭刷新個人（呼叫端
    /// 已經處理過個人）。用於個人切月後同步共用資料。
    private func refreshSharedForCurrentMonth() async {
        guard let m = currentMonth, let url = buildSharedMonthURL(for: m) else { return }
        do {
            let txList = try await txService.getTransactions(fullURL: url)
            applyPage(txList, fallbackMonth: m)
        } catch {
            /// Non-fatal: leave the stale shared data rather than surfacing an
            /// alert for a background-style refresh.
            /// 非致命錯誤：保留舊資料而不彈錯誤訊息。
        }
    }

    /// Build the "current month" shared transactions URL from a "yyyy-MM" string.
    /// 建立指定月份的共用交易 endpoint URL。
    private func buildSharedMonthURL(for month: String) -> String? {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let mNum = Int(parts[1]) else { return nil }
        return "\(APIClient.shared.baseURL)/transactions/?year=\(year)&month=\(mNum)"
    }

    /// Load a specific month of shared transactions using pagination URL
    /// 使用分页 URL 加载特定月份的共享交易
    ///
    /// Parameter: fullURL - Complete URL from previousMonthUrl or nextMonthUrl
    /// 参数: fullURL - 来自 previousMonthUrl 或 nextMonthUrl 的完整 URL
    func loadTransactions(fullURL: String) async {
        guard !isChangingMonth else { return }

        isChangingMonth = true
        isLoading       = true
        errorMessage    = nil

        let requestedMonth = Self.extractMonth(from: fullURL)
        if let requestedMonth {
            currentMonth = requestedMonth
            let urls = buildSharedMonthURLs(from: requestedMonth)
            previousMonthUrl = urls.previous
            nextMonthUrl = urls.next
        }

        defer {
            isChangingMonth = false
            isLoading = false
        }

        do {
            /// Fetch shared transactions using provided URL (pagination)
            /// 使用提供的 URL 獲取共用交易（分頁）
            let txList = try await txService.getTransactions(fullURL: fullURL)
            applyPage(txList, fallbackMonth: requestedMonth)

            /// Personal API is separate from shared account API, so always sync it
            /// to the same month whenever shared transactions are navigated.
            /// 個人 API 與共用帳戶 API 不同，每次切換共用帳本月份時都要同步個人資料。
            await loadPersonal(month: currentMonth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Convenience methods for pagination (分页便利方法)

    /// Load previous month of shared transactions
    /// (personal sync is handled inside loadTransactions)
    /// 加载共享交易的上个月（個人同步已在 loadTransactions 內處理）
    func loadPreviousMonth() async {
        guard let url = previousMonthUrl else { return }
        await loadTransactions(fullURL: url)
    }

    /// Load next month of shared transactions
    /// (personal sync is handled inside loadTransactions)
    /// 加载共享交易的下个月（個人同步已在 loadTransactions 內處理）
    func loadNextMonth() async {
        guard let url = nextMonthUrl else { return }
        await loadTransactions(fullURL: url)
    }

    /// MARK: - Helper: Apply Pagination Response (应用分页响应)

    /// Extract pagination info from API response and update state
    /// 从 API 响应提取分页信息并更新状态
    ///
    /// The backend returns pagination URLs in the response, e.g.:
    /// {
    ///   "results": [...],
    ///   "current_month": "2024-01",
    ///   "previous_month_url": "http://api.../transactions/?month=2023-12",
    ///   "next_month_url": "http://api.../transactions/?month=2024-02"
    /// }
    /// 后端在响应中返回分页 URL，例如:
    /// {
    ///   "results": [...],
    ///   "current_month": "2024-01",
    ///   "previous_month_url": "http://api.../transactions/?month=2023-12",
    ///   "next_month_url": "http://api.../transactions/?month=2024-02"
    /// }
    ///
    /// This method extracts that data into our @Observable properties
    /// 此方法将该数据提取到我们的 @Observable 属性中
    private func applyPage(_ list: PaginatedTransactionList, fallbackMonth: String? = nil) {
        transactions     = list.results
        /// Trust the requested month (fallbackMonth, derived from the URL we
        /// just called) over `list.currentMonth` — the backend may return its
        /// "latest transaction month" instead of the requested month, which
        /// would silently desync `currentMonth` from the actual data shown.
        /// 信任我們請求的月份（從剛剛打的 URL 解出），不採信後端的 current_month，
        /// 否則 currentMonth 可能與真正抓到的資料月份不一致。
        currentMonth     = fallbackMonth ?? list.currentMonth
        previousMonthUrl = list.previousMonthUrl
        nextMonthUrl     = list.nextMonthUrl

        /// Backfill pagination URLs if the API didn't return them, so the
        /// previous/next month buttons remain usable after navigating months.
        /// 若 API 沒有回傳分頁 URL，從目前月份自行建立，讓切月後按鈕仍可使用。
        if previousMonthUrl == nil || nextMonthUrl == nil, let m = currentMonth {
            let urls = buildSharedMonthURLs(from: m)
            if previousMonthUrl == nil { previousMonthUrl = urls.previous }
            if nextMonthUrl     == nil { nextMonthUrl     = urls.next }
        }
    }

    /// Build pagination URLs (previous/next month) for shared transactions
    /// from a "yyyy-MM" month string. Used as a fallback when the backend
    /// doesn't return them in the paginated response.
    /// 從 "yyyy-MM" 月份字串建立共用交易的上一月/下一月 URL，作為後端未回傳時的備援。
    private func buildSharedMonthURLs(from month: String) -> (previous: String?, next: String?) {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let mNum = Int(parts[1]) else {
            return (nil, nil)
        }
        let baseURL = APIClient.shared.baseURL
        let prevYear  = mNum == 1  ? year - 1 : year
        let prevMonth = mNum == 1  ? 12       : mNum - 1
        let nextYear  = mNum == 12 ? year + 1 : year
        let nextMonth = mNum == 12 ? 1        : mNum + 1
        let prev = "\(baseURL)/transactions/?year=\(prevYear)&month=\(prevMonth)"
        let next = "\(baseURL)/transactions/?year=\(nextYear)&month=\(nextMonth)"
        return (prev, next)
    }

    /// Extract a "yyyy-MM" month string from a transactions URL whose
    /// query string contains ?year=...&month=...
    /// 從含有 ?year=...&month=... 查詢字串的交易 URL 取出 "yyyy-MM" 月份字串。
    private static func extractMonth(from url: String) -> String? {
        guard let components = URLComponents(string: url),
              let items = components.queryItems else {
            return nil
        }

        if let yearStr = items.first(where: { $0.name == "year" })?.value,
           let monthStr = items.first(where: { $0.name == "month" })?.value,
           let monthInt = Int(monthStr) {
            return String(format: "%@-%02d", yearStr, monthInt)
        }

        if let month = items.first(where: { $0.name == "month" })?.value {
            let parts = month.split(separator: "-")
            if parts.count == 2,
               let year = Int(parts[0]),
               let monthInt = Int(parts[1]) {
                return String(format: "%04d-%02d", year, monthInt)
            }
        }

        return nil
    }

    /// Same as applyPage but for personal transactions.
    /// Also updates the master `currentMonth` so it stays in sync with every
    /// path that changes the active month, and backfills pagination URLs when
    /// the backend doesn't return them.
    /// 與 applyPage 相同但用於個人交易；同步更新 currentMonth，並在 API 未回傳
    /// 分頁 URL 時自行建立，避免任一處讀到舊月份。
    private func applyPersonalPage(_ list: PaginatedTransactionList, fallbackMonth: String? = nil) {
        /// Same priority as applyPage: trust the requested month over backend's
        /// returned `current_month`. Fall further back to existing personal /
        /// shared month state so we never end up with nil.
        /// 與 applyPage 相同：信任我們請求的月份，再依序退回既有狀態。
        let effectiveMonth = fallbackMonth ?? list.currentMonth ?? personalCurrentMonth ?? currentMonth

        personalTransactions     = list.results
        personalCurrentMonth     = effectiveMonth
        personalPreviousMonthUrl = list.previousMonthUrl
        personalNextMonthUrl     = list.nextMonthUrl

        /// Keep the master currentMonth in sync — it's the single source of truth.
        /// 同步主要 currentMonth — 它是月份的單一真相來源。
        if let m = effectiveMonth { currentMonth = m }

        /// Backfill pagination URLs if API didn't return them.
        /// 若 API 沒有回傳分頁 URL，從目前月份自行建立。
        if personalPreviousMonthUrl == nil || personalNextMonthUrl == nil,
           let m = effectiveMonth {
            let urls = buildPersonalMonthURLs(from: m)
            if personalPreviousMonthUrl == nil { personalPreviousMonthUrl = urls.previous }
            if personalNextMonthUrl     == nil { personalNextMonthUrl     = urls.next }
        }
    }

    /// Build pagination URLs (previous/next month) for personal transactions
    /// from a "yyyy-MM" month string. Mirrors `buildSharedMonthURLs` but hits
    /// the /transactions/mine/ endpoint.
    /// 建立個人交易的上一月/下一月 URL，端點為 /transactions/mine/。
    private func buildPersonalMonthURLs(from month: String) -> (previous: String?, next: String?) {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let mNum = Int(parts[1]) else {
            return (nil, nil)
        }
        let baseURL = APIClient.shared.baseURL
        let prevYear  = mNum == 1  ? year - 1 : year
        let prevMonth = mNum == 1  ? 12       : mNum - 1
        let nextYear  = mNum == 12 ? year + 1 : year
        let nextMonth = mNum == 12 ? 1        : mNum + 1
        let prev = "\(baseURL)/transactions/mine/?year=\(prevYear)&month=\(prevMonth)"
        let next = "\(baseURL)/transactions/mine/?year=\(nextYear)&month=\(nextMonth)"
        return (prev, next)
    }

    // MARK: - Per-Account Transactions (各帳戶交易載入)

    /// Load transactions for a specific shared account directly from its own
    /// endpoint `/accounts/{id}/transactions/`. Use this instead of client-side
    /// filtering of `transactions` whenever a view needs a particular account's
    /// authoritative data.
    /// 從各帳戶自身端點載入交易資料，取代從共用 `transactions` 自行篩選的做法，
    /// 確保資料與後端權威狀態一致。
    func loadAccountTransactions(accountId: String, month: String? = nil) async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let effectiveMonth = month ?? currentMonth ?? formatter.string(from: Date())
        do {
            let list = try await txService.getAccountTransactions(
                accountId: accountId,
                month:     effectiveMonth
            )
            applyAccountPage(accountId: accountId, list: list, fallbackMonth: effectiveMonth)
        } catch {
            /// Non-fatal: a specific account may be inaccessible; keep silent.
            /// 非致命：個別帳戶不可用時靜默處理，不彈錯誤訊息。
        }
    }

    /// Navigate a specific account's transactions via the pagination URL
    /// returned by the previous response.
    /// 使用先前回應提供的 URL 切換特定帳戶的月份。
    func loadAccountTransactionsMonth(accountId: String, fullURL: String) async {
        do {
            let list = try await txService.getAccountTransactions(
                accountId: accountId,
                fullURL:   fullURL
            )
            applyAccountPage(
                accountId:     accountId,
                list:          list,
                fallbackMonth: Self.extractMonth(from: fullURL)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Apply a paginated response to the per-account state and keep the master
    /// `currentMonth` synced (same single-source-of-truth rule as
    /// `applyPage` / `applyPersonalPage`).
    /// 套用回應到 accountStates[accountId]，並同步主要 currentMonth。
    private func applyAccountPage(accountId: String,
                                  list: PaginatedTransactionList,
                                  fallbackMonth: String? = nil) {
        var state = accountStates[accountId] ?? AccountState()
        let effectiveMonth = fallbackMonth ?? list.currentMonth ?? state.currentMonth ?? currentMonth

        state.transactions     = list.results
        state.currentMonth     = effectiveMonth
        state.previousMonthUrl = list.previousMonthUrl
        state.nextMonthUrl     = list.nextMonthUrl

        /// Backfill pagination URLs when the API doesn't return them.
        /// 後端未回傳分頁 URL 時，自行建立。
        if state.previousMonthUrl == nil || state.nextMonthUrl == nil,
           let m = effectiveMonth {
            let urls = buildAccountMonthURLs(accountId: accountId, from: m)
            if state.previousMonthUrl == nil { state.previousMonthUrl = urls.previous }
            if state.nextMonthUrl     == nil { state.nextMonthUrl     = urls.next }
        }

        accountStates[accountId] = state

        /// Sync master currentMonth — it's the single source of truth.
        /// 同步主要 currentMonth — 單一真相來源。
        if let m = effectiveMonth { currentMonth = m }
    }

    /// Build pagination URLs (previous/next month) for an account-scoped
    /// transactions endpoint.
    /// 建立指定帳戶的上一月/下一月分頁 URL。
    private func buildAccountMonthURLs(accountId: String,
                                       from month: String) -> (previous: String?, next: String?) {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let mNum = Int(parts[1]) else {
            return (nil, nil)
        }
        let baseURL = APIClient.shared.baseURL
        let prevYear  = mNum == 1  ? year - 1 : year
        let prevMonth = mNum == 1  ? 12       : mNum - 1
        let nextYear  = mNum == 12 ? year + 1 : year
        let nextMonth = mNum == 12 ? 1        : mNum + 1
        let prev = "\(baseURL)/accounts/\(accountId)/transactions/?year=\(prevYear)&month=\(prevMonth)"
        let next = "\(baseURL)/accounts/\(accountId)/transactions/?year=\(nextYear)&month=\(nextMonth)"
        return (prev, next)
    }

    // MARK: - CRUD Operations (增删改查操作)

    /// Create a new transaction and add it to the list
    /// 创建新交易并将其添加到列表
    ///
    /// Parameters (参数):
    /// - description: What the transaction is for (e.g., "Lunch at restaurant")
    ///   交易用途（例如，"午餐在餐厅"）
    /// - amount: String because it comes from a TextField in the UI
    ///   字符串因为它来自 UI 中的 TextField
    /// - currency: Optional (defaults to user's default currency)
    ///   可选的（默认为用户的默认货币）
    /// - type: .income or .expense (determines whether to add or subtract)
    ///   .income 或 .expense（确定是添加还是减去）
    /// - date: When the transaction occurred
    ///   交易发生的时间
    /// - categoryId: Optional category for the transaction
    ///   交易的可选类别
    /// - notes: Optional additional details
    ///   可选的附加详细信息
    /// - accountIds: Which shared accounts this belongs to
    ///   这属于哪些共享帐户
    ///
    /// Returns (返回): The created Transaction object (server-assigned ID, timestamp, etc.)
    /// 创建的 Transaction 对象（服务器分配的 ID、时间戳等）
    @discardableResult  // Caller can ignore the return value
                        // 调用者可以忽略返回值
    func createTransaction(
        description: String,
        amount: String,
        currency: String? = nil,
        type: TransactionType,
        date: Date,
        categoryId: String?,
        notes: String?,
        accountIds: [String]
    ) async throws -> Transaction {
        /// Convert Date to ISO 8601 string for API transmission
        /// 将 Date 转换为 ISO 8601 字符串以进行 API 传输
        let iso = ISO8601DateFormatter()

        /// Build request object (empty strings become nil for optional fields)
        /// 构建请求对象（空字符串对于可选字段变为 nil）
        let req = CreateTransactionRequest(
            description:     description,
            amount:          amount,
            currency:        currency?.isEmpty == true ? nil : currency,
            transactionType: type,
            transactionDate: iso.string(from: date),
            accountIds:      accountIds,
            categoryId:      categoryId,
            notes:           notes?.isEmpty == true ? nil : notes
        )

        /// Send to API and get back the created transaction (with server ID, timestamp)
        /// 发送到 API 并获取返回的创建交易（带有服务器 ID、时间戳）
        let tx = try await txService.createTransaction(req)

        /// Optimistic update: add to local list immediately
        /// Insert at index 0 so newest appears first
        /// 乐观更新: 立即添加到本地列表
        /// 在索引 0 处插入，最新的首先出现
        transactions.insert(tx, at: 0)

        return tx
    }

    /// Update an existing transaction
    /// 更新现有交易
    ///
    /// Flow (流程):
    /// 1. Convert Date to ISO 8601 string
    ///    将 Date 转换为 ISO 8601 字符串
    /// 2. Build request with updated fields
    ///    使用更新的字段构建请求
    /// 3. Send to API (PUT /api/transactions/{id}/)
    ///    发送到 API（PUT /api/transactions/{id}/）
    /// 4. Find the transaction in our list by ID
    ///    在我们的列表中按 ID 查找交易
    /// 5. Replace it with the new version
    ///    用新版本替换它
    @discardableResult
    func updateTransaction(
        id: String,
        description: String,
        amount: String,
        currency: String? = nil,
        type: TransactionType,
        date: Date,
        categoryId: String?,
        notes: String?,
        accountIds: [String]
    ) async throws -> Transaction {
        let iso = ISO8601DateFormatter()
        let req = CreateTransactionRequest(
            description:     description,
            amount:          amount,
            currency:        currency?.isEmpty == true ? nil : currency,
            transactionType: type,
            transactionDate: iso.string(from: date),
            accountIds:      accountIds,
            categoryId:      categoryId,
            notes:           notes?.isEmpty == true ? nil : notes
        )

        /// Call update API endpoint
        /// 调用更新 API 端点
        let tx = try await txService.updateTransaction(id: id, req: req)

        /// Optimistic update: replace in local list
        /// 乐观更新: 在本地列表中替换
        /// firstIndex(where:) finds the position of the matching transaction
        /// firstIndex(where:) 找到匹配的交易的位置
        if let idx = transactions.firstIndex(where: { $0.id == id }) {
            transactions[idx] = tx
        }

        return tx
    }

    /// Delete a transaction by ID
    /// 通过 ID 删除交易
    ///
    /// Note: Errors are captured but not thrown (non-critical)
    /// 注意: 错误被捕获但未抛出（非关键）
    func deleteTransaction(id: String) async {
        do {
            /// Call delete API endpoint
            /// 调用删除 API 端点
            try await txService.deleteTransaction(id: id)

            /// Optimistic update: remove from both lists
            /// 乐观更新: 从两个列表中移除
            /// (might be in shared or personal list)
            /// (可能在共享或个人列表中)
            transactions.removeAll         { $0.id == id }
            personalTransactions.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Client-side Computation (客户端计算)

    /// Compute per-currency income/expense/balance summary
    /// 计算按货币的收入/支出/余额摘要
    ///
    /// Key Design: All calculation happens on the CLIENT (not on server)
    /// This allows instant updates as user edits transactions
    /// 关键设计: 所有计算都在客户端进行（不在服务器上）
    /// 这允许当用户编辑交易时即时更新
    ///
    /// Parameters (参数):
    /// - accountId: nil → all shared transactions
    ///             "personal" → personal transactions only
    ///             "account-123" → transactions in that account
    ///
    /// Returns (返回): TransactionSummary with per-currency breakdown
    /// 返回: 包含按货币分解的 TransactionSummary
    func summary(forAccountId accountId: String?) -> TransactionSummary {
        /// Step 1: Filter transactions based on accountId
        /// 步骤 1: 根据 accountId 过滤交易
        let txs = slice(for: accountId)

        /// Step 2: Group amounts by currency
        /// 步骤 2: 按货币分组金额
        /// incomeMap: { "USD": 5000, "TWD": 10000, ... }
        /// expenseMap: { "USD": 2000, "TWD": 3000, ... }
        var incomeMap:  [String: Double] = [:]
        var expenseMap: [String: Double] = [:]

        for tx in txs {
            /// Get currency from transaction (default to TWD)
            /// 从交易中获取货币（默认为 TWD）
            let cur = tx.currency ?? "TWD"

            /// Convert amount string to Double
            /// 将金额字符串转换为 Double
            let amt = Double(tx.amount) ?? 0

            /// Add to income or expense map based on transaction type
            /// 根据交易类型添加到收入或支出图中
            if tx.transactionType == .income {
                incomeMap[cur, default: 0]  += amt
            } else {
                expenseMap[cur, default: 0] += amt
            }
        }

        /// Step 3: Create CurrencyAmount for each currency
        /// 步骤 3: 为每种货币创建 CurrencyAmount
        /// Combine all currencies seen (even if one had only income or only expense)
        /// 组合所有看到的货币（即使一个只有收入或只有支出）
        let allCurrencies = Set(incomeMap.keys).union(expenseMap.keys)

        var amounts = allCurrencies.map { cur in
            CurrencyAmount(
                currency: cur,
                income:  incomeMap[cur, default: 0],
                expense: expenseMap[cur, default: 0]
            )
        }

        /// Step 4: Sort by volume (income + expense) - most active currencies first
        /// 步骤 4: 按体积排序（收入 + 支出） - 最活跃的货币优先
        amounts.sort { $0.volume > $1.volume }

        /// Step 5: Wrap in summary object
        /// 步骤 5: 包装在摘要对象中
        return TransactionSummary(currencies: amounts)
    }

    /// Breakdown expenses by category
    /// 按类别分解支出
    ///
    /// Purpose (目的):
    /// Views use this to show pie charts like:
    /// "Groceries: 40%, Dining: 30%, Shopping: 30%"
    /// 视图使用此来显示饼图，如:
    /// "Groceries: 40%, Dining: 30%, Shopping: 30%"
    ///
    /// Multi-currency: Groups amounts by currency within each category
    /// 多货币: 在每个类别内按货币分组金额
    ///
    /// Returns (返回): Array of CategoryBreakdownItem, sorted by total expense descending
    /// 返回: CategoryBreakdownItem 数组，按总支出降序排序
    func categoryBreakdown(forAccountId accountId: String?, categories: [Category]) -> [CategoryBreakdownItem] {
        /// Filter to only expenses (income doesn't get categorized in this view)
        /// 仅过滤支出（收入在此视图中不被分类）
        let expenses = slice(for: accountId).filter { $0.transactionType == .expense }

        /// Guard: if no expenses, return empty breakdown
        /// 防护: 如果没有支出，返回空分解
        guard !expenses.isEmpty else { return [] }

        /// Build lookup: category name → category object
        /// Important: tx.category is the read-only name returned by GET
        ///            tx.categoryId is write-only (never in GET response)
        /// 构建查找: 类别名称 → 类别对象
        /// 重要: tx.category 是 GET 返回的只读名称
        ///      tx.categoryId 是只写的（从不在 GET 响应中）
        let catMapByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })

        /// Group expenses: category name → (currency → amount)
        /// 分组支出: 类别名称 → (货币 → 金额)
        /// totals["Food"]["USD"] = 100.0
        /// totals["Food"]["TWD"] = 500.0
        var totals: [String: [String: Double]] = [:]

        for tx in expenses {
            /// Get category name (or "__none__" if uncategorized)
            /// 获取类别名称（或"__none__"如果未分类）
            let key = tx.category ?? "__none__"

            /// Get currency (default TWD)
            /// 获取货币（默认 TWD）
            let cur = tx.currency ?? "TWD"

            /// Add amount to the mapping
            /// 将金额添加到映射中
            totals[key, default: [:]][cur, default: 0] += Double(tx.amount) ?? 0
        }

        /// Convert to CategoryBreakdownItem array
        /// 转换为 CategoryBreakdownItem 数组
        var items: [CategoryBreakdownItem] = totals.compactMap { key, curMap in
            /// Convert currency map to array, sorted by amount
            /// 将货币图转换为数组，按金额排序
            let perCurrency = curMap.map { CurrencyTotal(currency: $0.key, amount: $0.value) }
                .sorted { $0.amount > $1.amount }

            /// Calculate total across all currencies
            /// 计算所有货币的总计
            let grandTotal = perCurrency.reduce(0) { $0 + $1.amount }

            /// Skip if total is zero
            /// 如果总数为零则跳过
            guard grandTotal > 0 else { return nil }

            /// Handle uncategorized transactions
            /// 处理未分类的交易
            if key == "__none__" {
                return CategoryBreakdownItem(
                    id: key,
                    name: "其他",  // Chinese: "Other"
                    icon: nil,
                    total: grandTotal,
                    perCurrency: perCurrency
                )
            }

            /// Get category icon from lookup
            /// 从查找中获取类别图标
            let cat = catMapByName[key]
            return CategoryBreakdownItem(
                id: key,
                name: key,
                icon: cat?.icon,
                total: grandTotal,
                perCurrency: perCurrency
            )
        }

        /// Sort by total expense descending (most expensive first)
        /// 按总支出降序排序（最昂贵的优先）
        items.sort { $0.total > $1.total }
        return items
    }

    /// MARK: - Filter Helper (过滤帮助器)

    /// Return transactions for a specific account (or all)
    /// 返回特定帐户的交易（或全部）
    ///
    /// Logic (逻辑):
    /// - accountId == nil: return shared transactions (from /api/transactions/)
    ///   accountId == nil: 返回共享交易（来自 /api/transactions/）
    /// - accountId == "personal": return personal transactions (from /api/transactions/mine/)
    ///   accountId == "personal": 返回个人交易（来自 /api/transactions/mine/）
    /// - otherwise: filter shared transactions by account ID
    ///   否则: 按帐户 ID 过滤共享交易
    private func slice(for accountId: String?) -> [Transaction] {
        switch accountId {
        case nil:
            /// All shared account transactions (aggregate view)
            /// 所有共享帐户交易（總計視圖）
            return transactions

        case "personal":
            /// Personal (non-shared) transactions only
            /// 仅个人（非共享）交易
            return personalTransactions

        case let .some(id):
            /// Per-account authoritative data from `/accounts/{id}/transactions/`.
            /// We deliberately do NOT fall back to filtering `transactions` —
            /// that aggregated view can drift from the per-account endpoint
            /// when other users modify the account, which is exactly the bug
            /// this change fixes. Empty array until the account is loaded.
            /// 取用各帳戶權威端點資料；不退回 client filter，避免他人修改後資料
            /// 不同步。資料未載入前為空陣列，由 View 觸發 loadAccountTransactions。
            return accountStates[id]?.transactions ?? []
        }
    }

    // MARK: - AI-Powered Parsing (人工智能解析)

    /// Send text to backend for AI parsing (OCR, NLP, etc.)
    /// 将文本发送到后端进行 AI 解析（OCR、NLP 等）
    ///
    /// Purpose (目的):
    /// User takes a photo of a receipt or speaks notes like:
    /// "Lunch at Chipotle, $12.50, card payment"
    /// Backend parses this and returns suggested transactions
    /// 用户拍摄收据照片或说明笔记，如:
    /// "午餐在 Chipotle，$12.50，卡付款"
    /// 后端解析并返回建议的交易
    ///
    /// Returns (返回): Array of draft Transaction objects (for preview before creation)
    /// 返回: 草稿 Transaction 对象数组（用于创建前预览）
    func parseOnly(text: String, source: ParseSource? = nil) async throws -> [Transaction] {
        /// Show loading indicator
        /// 显示加载指示器
        isLoading = true
        defer {
            /// Always hide loading indicator, even if error occurs
            /// 总是隐藏加载指示器，即使发生错误
            isLoading = false
        }

        /// Send to backend for parsing
        /// 发送到后端进行解析
        return try await txService.parseText(text, source: source)
    }

    /// Update a batch of parse-result drafts on the server.
    /// 批量更新 parse 結果草稿到伺服器。
    ///
    /// Strategy (策略):
    /// - If the backend saved the transaction during parse, PATCH the existing record.
    ///   若後端在 parse 時已存入 DB，使用 PATCH 更新現有記錄，避免重複建立。
    /// - If PATCH returns an error (e.g. 404 – the parse didn't save), fall back to POST.
    ///   若 PATCH 失敗（後端沒有存入），退而使用 POST 建立新記錄。
    @discardableResult
    func updateBatch(_ drafts: [DraftTransaction]) async throws -> [Transaction] {
        var newlyCreated: [Transaction] = []
        let iso = ISO8601DateFormatter()

        for draft in drafts {
            let req = CreateTransactionRequest(
                description:     draft.description,
                amount:          draft.amount,
                currency:        draft.currency.isEmpty ? nil : draft.currency,
                transactionType: draft.transactionType,
                transactionDate: iso.string(from: draft.transactionDate),
                accountIds:      draft.accountIds,
                categoryId:      draft.categoryId,
                notes:           draft.notes?.isEmpty == true ? nil : draft.notes
            )

            do {
                // Try PATCH first (backend may have already saved this transaction)
                // 先嘗試 PATCH（後端可能已在 parse 時存入）
                let tx = try await txService.updateTransaction(id: draft.originalId, req: req)
                // Replace in local list if found; otherwise stage for front-insert
                // 若本地列表有此筆則替換；否則暫存待插入最前面
                if let idx = transactions.firstIndex(where: { $0.id == draft.originalId }) {
                    transactions[idx] = tx
                } else {
                    newlyCreated.append(tx)
                }
            } catch {
                // Fallback: backend didn't save during parse → create a new transaction
                // 退而求其次：後端 parse 時未存入 → 改用 POST 建立新記錄
                let tx = try await txService.createTransaction(req)
                newlyCreated.append(tx)
            }
        }

        if !newlyCreated.isEmpty {
            transactions.insert(contentsOf: newlyCreated, at: 0)
        }
        return newlyCreated
    }

    /// Silently delete transactions that were auto-saved by the parse endpoint.
    /// Called when the user cancels the preview without wanting to keep the results.
    /// 靜默刪除 parse 端點自動儲存的交易（使用者取消 preview 時呼叫）。
    /// Errors are ignored: if the parse didn't save, the IDs won't exist and that's fine.
    /// 忽略錯誤：若後端 parse 未存入，這些 ID 根本不存在，靜默略過即可。
    func deleteParsed(ids: [String]) async {
        for id in ids {
            try? await txService.deleteTransaction(id: id)
            transactions.removeAll         { $0.id == id }
            personalTransactions.removeAll { $0.id == id }
        }
    }

    /// Batch-create multiple draft transactions
    /// 批量创建多个草稿交易
    ///
    /// Purpose (目的):
    /// After parseOnly() returns draft transactions, user confirms them
    /// This method creates all of them at once (instead of one at a time)
    /// 在 parseOnly() 返回草稿交易后，用户确认它们
    /// 此方法一次创建所有交易（而不是逐个创建）
    ///
    /// Returns (返回): Array of created Transaction objects (with server-assigned IDs)
    /// 返回: 创建的 Transaction 对象数组（带有服务器分配的 ID）
    @discardableResult
    func createBatch(_ drafts: [DraftTransaction]) async throws -> [Transaction] {
        /// Collect all created transactions
        /// 收集所有创建的交易
        var created: [Transaction] = []

        /// Create transactions one at a time
        /// (Could be optimized with batch endpoint, but sequential is simpler)
        /// 逐个创建交易
        /// （可以使用批处理端点优化，但顺序更简单）
        for draft in drafts {
            /// Convert Date to ISO 8601 string
            /// 将 Date 转换为 ISO 8601 字符串
            let iso = ISO8601DateFormatter()

            /// Build request from draft
            /// 从草稿构建请求
            let req = CreateTransactionRequest(
                description:     draft.description,
                amount:          draft.amount,
                currency:        draft.currency.isEmpty ? nil : draft.currency,
                transactionType: draft.transactionType,
                transactionDate: iso.string(from: draft.transactionDate),
                accountIds:      draft.accountIds,
                categoryId:      draft.categoryId,
                notes:           draft.notes?.isEmpty == true ? nil : draft.notes
            )

            /// Create transaction on server
            /// 在服务器上创建交易
            let tx = try await txService.createTransaction(req)
            created.append(tx)
        }

        /// Add all created transactions to the beginning of the list
        /// (newest first)
        /// 将所有创建的交易添加到列表的开头
        /// （最新的优先）
        transactions.insert(contentsOf: created, at: 0)

        return created
    }
}
