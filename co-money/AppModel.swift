import Foundation
import MMCore
import SwiftUI

/// 連哪一台後端。Debug 預設 staging，Release 預設正式環境；「我」頁面可以切換。
enum Server: String, CaseIterable, Identifiable {
    case staging
    case production

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .staging: URL(string: "https://newsroom.codai8.com/")!
        case .production: URL(string: "https://codai8.com/")!
        }
    }

    var label: String { self == .staging ? "測試（staging）" : "正式" }

    static var saved: Server {
        if let raw = UserDefaults.standard.string(forKey: "server"), let server = Server(rawValue: raw) {
            return server
        }
        #if DEBUG
        return .staging
        #else
        // 正式環境（codai8.com）還沒有 v2 API，在上線之前 Release 也先連 staging。
        // 後端上線後改回 .production（REQUIREMENTS A8）。
        return .staging
        #endif
    }
}

/// 整個 app 的狀態。畫面只讀這裡的資料、呼叫這裡的方法。
///
/// 資料的來源：先顯示快取（離線也看得到），連得上就更新（ios-design §4）。
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case loggedOut
        case ready
    }

    // MARK: 狀態

    private(set) var phase: Phase = .starting
    private(set) var server: Server
    private(set) var userId: Int?
    private(set) var username = ""

    private(set) var ledgers: [Ledger] = []
    private(set) var selectedLedgerId: UUID?
    /// 使用者選的月份；nil 是「本月」。首頁、交易、預算三個分頁共用，切換分頁不會變。
    private var selectedMonth: YearMonth?

    /// 本月：依帳本的時區，不是手機的（§4.5）。每次讀都重算，跨月時自動換。
    var currentMonth: YearMonth { YearMonth(Date(), in: timeZone) }
    /// 三個分頁共用的月份。
    var month: YearMonth { selectedMonth ?? currentMonth }
    var isCurrentMonth: Bool { month == currentMonth }

    /// 可以選的月份：最近 12 個月，新的在前。
    var monthOptions: [YearMonth] {
        (0..<12).map { offset in (0..<offset).reduce(currentMonth) { month, _ in month.previous } }
    }

    private(set) var summary: [CategorySummaryItem] = []
    private(set) var previousSummary: [CategorySummaryItem] = []
    private(set) var tags: [Tag] = []
    /// 選定月份的交易。
    private(set) var transactions: [MMCore.Transaction] = []
    private(set) var parseJobs: [ParseJob] = []
    private(set) var outboxItems: [OutboxItem] = []

    /// 最後一次成功從後端拿到資料的時間（離線時顯示「資料更新於 10:42」）。
    private(set) var updatedAt: Date?
    private(set) var isLoading = false
    /// 最後一次讀資料失敗的原因（顯示在畫面上方，不擋住操作）。
    private(set) var loadError: String?
    /// refresh token 失效了，但還有待上傳的資料：提示重新登入（§3.3）。
    private(set) var needsRelogin = false

    let connectivity = Connectivity()

    // MARK: 依賴

    @ObservationIgnored private(set) var api: APIClient
    @ObservationIgnored private var outbox: Outbox
    @ObservationIgnored private var cache: JSONCache
    @ObservationIgnored let attachments: URL

    init() {
        let server = Server.saved
        self.server = server
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        attachments = support.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let services = Self.makeServices(server: server, support: support, attachments: attachments)
        api = services.api
        outbox = services.outbox
        cache = services.cache
        selectedLedgerId = UserDefaults.standard.string(forKey: "selectedLedger").flatMap(UUID.init(uuidString:))
    }

    private static func makeServices(server: Server, support: URL, attachments: URL)
        -> (api: APIClient, outbox: Outbox, cache: JSONCache) {
        let transport = URLSessionTransport()
        let session = AuthSession(baseURL: server.url, transport: transport,
                                  store: KeychainTokenStore(service: "mm.\(server.rawValue)"))
        let api = APIClient(baseURL: server.url, transport: transport, session: session)
        let folder = support.appendingPathComponent(server.rawValue, isDirectory: true)
        let outbox = Outbox(store: FileOutboxStore(url: folder.appendingPathComponent("outbox.json")),
                            sender: APIOutboxSender(client: api, attachments: attachments),
                            attachments: attachments)
        return (api, outbox, JSONCache(directory: folder.appendingPathComponent("cache", isDirectory: true)))
    }

    // MARK: 衍生資料

    var selectedLedger: Ledger? {
        ledgers.first { $0.id == selectedLedgerId } ?? ledgers.first
    }

    var timeZone: TimeZone { selectedLedger?.timeZone ?? .current }

    var today: LocalDate { LocalDate(Date(), in: timeZone) }

    /// 本月花費：各分類淨額的加總（只算已經上傳的，§4.5）。
    var monthSpent: Money { summary.reduce(.zero) { $0 + $1.netAmount } }

    /// 和上個月比的變化（-0.08 是少 8%）。上個月沒有花費時是 nil。
    var monthChange: Double? {
        let previous = previousSummary.reduce(Money.zero) { $0 + $1.netAmount }
        guard previous.value > 0 else { return nil }
        return NSDecimalNumber(decimal: (monthSpent.value - previous.value) / previous.value).doubleValue
    }

    var budgets: [Tag] { tags.filter { $0.budgetAmount != nil } }

    /// 期間和選定月份有重疊的 tag（沒有期間的「一次性」tag 每個月都算）。
    var monthTags: [Tag] { tags.filter { overlapsMonth($0) } }

    /// 首頁的預算卡：選定月份內、有預算金額的 tag。
    var monthBudgets: [Tag] { monthTags.filter { $0.budgetAmount != nil } }

    func overlapsMonth(_ tag: Tag) -> Bool {
        let first = LocalDate(year: month.year, month: month.month, day: 1)
        let next = month.next
        let nextFirst = LocalDate(year: next.year, month: next.month, day: 1)
        if let start = tag.periodStart, start >= nextFirst { return false }
        if let end = tag.periodEnd, end < first { return false }
        return true
    }

    /// 這個帳本、選定月份還沒上傳的交易（列表上標「等待上傳」）。
    var pendingTransactions: [TransactionInput] {
        outboxItems.compactMap {
            guard case .createTransaction(let input) = $0.operation, input.ledgerId == selectedLedger?.id,
                  month.contains(input.transactionDate, in: timeZone) else { return nil }
            return input
        }
    }

    /// 解析好、等使用者確認的。
    var readyJobs: [ParseJob] { parseJobs.filter { $0.status == .done && !resolvedJobIds.contains($0.id) } }
    var failedJobs: [ParseJob] { parseJobs.filter { $0.status == .failed && !resolvedJobIds.contains($0.id) } }

    /// 已經按了「加入」或「捨棄」、但還在待上傳佇列的解析工作。
    /// 後端還沒收到時工作仍是 DONE，不排除的話重新整理後會又出現在待確認。
    private var resolvedJobIds: Set<UUID> {
        Set(outboxItems.compactMap { item in
            switch item.operation {
            case .confirmParseJob(let id, _), .discardParseJob(let id): id
            default: nil
            }
        })
    }
    var attentionItems: [OutboxItem] { outboxItems.filter(\.needsAttention) }
    var waitingItems: [OutboxItem] { outboxItems.filter { !$0.needsAttention } }

    /// 首頁「待處理」的數字。
    var inboxCount: Int { readyJobs.count + failedJobs.count + attentionItems.count }

    var isOffline: Bool { !connectivity.isOnline }

    // MARK: 啟動與登入

    func start() async {
        connectivity.onReconnect = { [weak self] in
            Task { await self?.syncNow() }
        }
        connectivity.start()
        await loadSession()
    }

    private func loadSession() async {
        userId = await api.session.userId
        guard let userId else {
            await prepareLoggedOut()
            return
        }
        UserDefaults.standard.set(userId, forKey: lastUserKey)
        username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        loadFromCache()
        phase = .ready
        await syncNow()
    }

    /// 沒有 token 時的畫面。如果上次登入的人還有待上傳的資料，代表是登入過期（不是主動登出），
    /// 要顯示「重新登入」並預先填好帳號（§3.3）。token 在 refresh 被拒絕時就清掉了，
    /// 所以只能靠記下來的使用者 id 去找待上傳的資料。
    private func prepareLoggedOut() async {
        outboxItems = []
        needsRelogin = false
        if let last = UserDefaults.standard.object(forKey: lastUserKey) as? Int {
            let items = await outbox.items(for: last)
            if !items.isEmpty {
                outboxItems = items
                username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
                needsRelogin = true
            }
        }
        phase = .loggedOut
    }

    private var usernameKey: String { "username.\(server.rawValue)" }
    private var lastUserKey: String { "lastUser.\(server.rawValue)" }

    func login(username: String, password: String) async throws {
        try await api.session.login(username: username, password: password)
        let newUser = await api.session.userId
        if newUser != userId {
            // 換了一個人：不能看到上一個人的快取。
            cache.clear()
            clearData()
        }
        userId = newUser
        self.username = username
        UserDefaults.standard.set(username, forKey: usernameKey)
        UserDefaults.standard.set(newUser, forKey: lastUserKey)
        needsRelogin = false
        phase = .ready
        await syncNow()
    }

    /// 有待上傳的資料時，畫面要先警告（§3.3）。
    var hasUnsentData: Bool { !outboxItems.isEmpty }

    func logout() async {
        await api.session.logout()
        cache.clear()
        clearData()
        userId = nil
        needsRelogin = false
        // 主動登出不是「登入過期」，下次開啟不要顯示重新登入的提示。
        UserDefaults.standard.removeObject(forKey: lastUserKey)
        phase = .loggedOut
    }

    /// 清掉畫面上所有從後端讀來的資料（換帳號、登出、換伺服器時）。
    private func clearData() {
        ledgers = []
        transactions = []
        selectedMonth = nil
        summary = []
        previousSummary = []
        tags = []
        parseJobs = []
        outboxItems = []
        updatedAt = nil
        loadError = nil
    }

    func switchServer(to server: Server) async {
        guard server != self.server else { return }
        // 等正在跑的同步結束，免得它把舊伺服器的資料寫進新的狀態。
        await syncTask?.value
        UserDefaults.standard.set(server.rawValue, forKey: "server")
        self.server = server
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let services = Self.makeServices(server: server, support: support, attachments: attachments)
        api = services.api
        outbox = services.outbox
        cache = services.cache
        clearData()
        userId = nil
        needsRelogin = false
        phase = .starting
        await loadSession()
    }

    // MARK: 同步

    @ObservationIgnored private var syncTask: Task<Void, Never>?

    /// 換 token、送出待上傳、再重新讀資料。app 啟動、回到前景、網路恢復時呼叫。
    /// 已經有一個在跑的話就等它，不會同時跑兩個。
    func syncNow() async {
        if let syncTask {
            await syncTask.value
            return
        }
        let task = Task { await performSync() }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func performSync() async {
        guard let userId else { return }
        // 先載入待上傳的項目：token 失效時要靠它決定是登出還是提示重新登入。
        outboxItems = await outbox.items(for: userId)
        // 啟動、回前景時先換一次 token（§3.3）。沒網路不算失敗，token 留著下次再換。
        do {
            _ = try await api.session.refresh(rejected: nil)
        } catch {
            handle(error)
            if phase != .ready || needsRelogin { return }
        }
        await outbox.retryNow()
        await drainOutbox()
        await refreshAll()
    }

    func refreshAll() async {
        guard phase == .ready else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            ledgers = try await api.ledgers()
            cache.save(ledgers, key: "ledgers")
            if selectedLedgerId == nil || !ledgers.contains(where: { $0.id == selectedLedgerId }) {
                // 預設選家庭帳本：記帳通常是記家裡的。
                setSelectedLedger(ledgers.first { $0.kind == .family }?.id ?? ledgers.first?.id)
            }
            parseJobs = try await api.parseJobs(status: [.done, .failed])
            await refreshLedgerData()
        } catch {
            handle(error)
        }
    }

    /// 讀目前帳本、選定月份的資料。
    func refreshLedgerData() async {
        guard phase == .ready, let ledger = selectedLedger else { return }
        let requested = month
        let key = "\(ledger.id.apiString)-\(requested)"
        do {
            async let summary = api.categorySummary(ledger: ledger.id, month: requested)
            async let previous = api.categorySummary(ledger: ledger.id, month: requested.previous)
            async let tags = api.activeTags(ledger: ledger.id)
            async let transactions = api.transactions(ledger: ledger.id, month: requested)
            let snapshot = LedgerSnapshot(summary: try await summary, previousSummary: try await previous,
                                          tags: try await tags, transactions: try await transactions)
            cache.save(snapshot, key: key)
            guard month == requested, selectedLedgerId == ledger.id else { return }  // 等的時候使用者又換了
            apply(snapshot)
            updatedAt = Date()
            loadError = nil
        } catch {
            handle(error)
            if month == requested, let cached = cache.load(LedgerSnapshot.self, key: key) {
                apply(cached.value)
                updatedAt = cached.updatedAt
            }
        }
    }

    func selectLedger(_ id: UUID) async {
        guard id != selectedLedgerId else { return }
        setSelectedLedger(id)
        clearLedgerData()
        loadFromCache()
        await refreshLedgerData()
    }

    private func setSelectedLedger(_ id: UUID?) {
        selectedLedgerId = id
        UserDefaults.standard.set(id?.uuidString, forKey: "selectedLedger")
    }

    /// 換月份：首頁、交易、預算三個分頁一起換。
    func changeMonth(to month: YearMonth) async {
        guard month != self.month else { return }
        selectedMonth = month == currentMonth ? nil : month
        // 先清掉上一個月的數字，再顯示快取；不然載入期間會看到別的月份的資料。
        clearLedgerData()
        loadFromCache()
        await refreshLedgerData()
    }

    private func clearLedgerData() {
        transactions = []
        summary = []
        previousSummary = []
        tags = []
    }

    private func apply(_ snapshot: LedgerSnapshot) {
        summary = snapshot.summary
        previousSummary = snapshot.previousSummary
        tags = snapshot.tags
        transactions = snapshot.transactions.sorted { $0.transactionDate > $1.transactionDate }
    }

    private func loadFromCache() {
        if let cached = cache.load([Ledger].self, key: "ledgers") {
            ledgers = cached.value
            updatedAt = cached.updatedAt
        }
        if let ledger = selectedLedger,
           let cached = cache.load(LedgerSnapshot.self, key: "\(ledger.id.apiString)-\(month)") {
            apply(cached.value)
            updatedAt = cached.updatedAt
        }
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }  // 下拉重新整理被取消，不是錯誤
        guard let error = error as? APIError else {
            loadError = error.localizedDescription
            return
        }
        switch error {
        case .unauthorized:
            if hasUnsentData {
                needsRelogin = true
            } else {
                phase = .loggedOut
            }
        case .offline:
            loadError = nil  // 離線有橫幅了
        case .server:
            // 讀取失敗不會讓資料不見：已上傳的在伺服器上，還沒上傳的留在手機的待上傳佇列。
            loadError = "伺服器暫時有問題・顯示的是上次更新的資料"
        default:
            loadError = error.message
        }
    }

    private func drainOutbox() async {
        guard let userId else { return }
        let report = await outbox.drain(userId: userId)
        if report.stoppedForLogin { needsRelogin = true }
        outboxItems = await outbox.items(for: userId)
        if !report.sent.isEmpty { await refreshLedgerData() }
        await scheduleRetry()
    }

    @ObservationIgnored private var retryTask: Task<Void, Never>?

    /// 排下一次重試（5 秒、30 秒、2 分、10 分，之後每 30 分，§4.3）。
    /// 沒有這個的話，app 開著時失敗的項目要等到下次回前景或網路恢復才會再送。
    private func scheduleRetry() async {
        retryTask?.cancel()
        retryTask = nil
        guard !needsRelogin, let userId, let next = await outbox.nextAttemptDate(userId: userId) else { return }
        let delay = max(1, next.timeIntervalSinceNow)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.drainOutbox()
        }
    }

    // MARK: 寫入（全部經過待上傳，§4）

    /// 記一筆。先存進待上傳，再試著送出；沒網路也不會失敗（§0 原則 2）。
    func add(_ input: TransactionInput) async {
        await enqueue(.createTransaction(input))
    }

    /// 送出解析工作，然後在畫面上等最多 30 秒（§2.2）。
    ///
    /// - Returns: 解析好（或失敗）的工作；沒網路或等不到時是 nil，結果之後會出現在「待處理」。
    func submitParse(_ upload: ParseJobUpload) async -> ParseJob? {
        await enqueue(.createParseJob(upload))
        guard !outboxItems.contains(where: { $0.operation == .createParseJob(upload) }) else {
            return nil  // 還沒送出去
        }
        return await waitForParse(upload.id)
    }

    /// 在畫面上等解析結果，最多 30 秒。
    func waitForParse(_ id: UUID) async -> ParseJob? {
        let api = self.api
        let job = try? await ParseJobWaiter.wait(for: id, fetch: { try await api.parseJob($0) })
        await refreshParseJobs()
        return job
    }

    func confirm(_ job: ParseJob, transactions: [TransactionInput]) async {
        parseJobs.removeAll { $0.id == job.id }
        await enqueue(.confirmParseJob(jobId: job.id, transactions: transactions))
    }

    func discard(_ job: ParseJob) async {
        parseJobs.removeAll { $0.id == job.id }
        await enqueue(.discardParseJob(jobId: job.id))
    }

    /// 請後端重跑解析（不重新上傳）。需要連線。
    /// - Returns: 失敗的原因；成功是 nil。
    func retry(_ job: ParseJob) async -> String? {
        do {
            let updated = try await api.retryParseJob(job.id)
            parseJobs = parseJobs.map { $0.id == job.id ? updated : $0 }
            return nil
        } catch {
            handle(error)
            return (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// 修改「需要處理」的待上傳項目後重新送出。
    func resubmit(_ item: OutboxItem, with operation: OutboxOperation) async {
        await outbox.replace(item.id, with: operation)
        await drainOutbox()
    }

    func removeFromOutbox(_ item: OutboxItem) async {
        await outbox.remove(item.id)
        if let userId { outboxItems = await outbox.items(for: userId) }
    }

    /// 修改已上傳的交易（需要連線，不進待上傳佇列；N9）。
    func update(_ transaction: MMCore.Transaction, with input: TransactionInput) async throws {
        _ = try await api.updateTransaction(transaction.id, with: input)
        await refreshLedgerData()
    }

    func delete(_ transaction: MMCore.Transaction) async throws {
        try await api.deleteTransaction(transaction.id)
        transactions.removeAll { $0.id == transaction.id }
        await refreshLedgerData()
    }

    func refreshParseJobs() async {
        if let jobs = try? await api.parseJobs(status: [.done, .failed]) { parseJobs = jobs }
    }

    /// 把錄音 / 照片存進附件資料夾，回傳檔名（放進 ParseJobUpload）。
    func saveAttachment(_ data: Data, extension ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try data.write(to: attachments.appendingPathComponent(name), options: .atomic)
        return name
    }

    func newAttachmentURL(extension ext: String) -> (name: String, url: URL) {
        let name = "\(UUID().uuidString).\(ext)"
        return (name, attachments.appendingPathComponent(name))
    }

    private func enqueue(_ operation: OutboxOperation) async {
        guard let userId else { return }
        await outbox.enqueue(operation, userId: userId)
        await drainOutbox()
    }
}

/// 一個帳本、一個月的資料，整份存進快取。
struct LedgerSnapshot: Codable, Sendable {
    var summary: [CategorySummaryItem]
    var previousSummary: [CategorySummaryItem]
    var tags: [Tag]
    var transactions: [MMCore.Transaction]
}
