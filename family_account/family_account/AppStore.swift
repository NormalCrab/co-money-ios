//
//  AppStore.swift
//  family_account
//
//  單一資料來源（single source of truth）。
//  - 所有資料變動都經過這裡，並自動存成 JSON 檔（App 重開資料不消失）。
//  - 之後接 Django 後端時，把這裡的本機操作換成 API 呼叫即可，View 不用動。
//

import Foundation
import Observation

@Observable
final class AppStore {
    // MARK: - State

    var members: [Member] = []
    var currentMemberID: UUID = UUID()
    var invitations: [FamilyInvitation] = []
    var transactions: [TransactionItem] = []
    var pendingFixedExpenses: [FixedExpense] = []
    var syncQueue: [SyncChange] = []
    var projects: [ProjectDefinition] = []
    var budget = BudgetPlan(total: 50_000, categoryLimits: [:])
    var isSyncing = false
    var lastSyncText = "尚未同步"

    private let calendar = Calendar.current

    // MARK: - Init / Persistence

    /// 存檔用的快照結構。
    private struct Snapshot: Codable {
        var members: [Member]
        var currentMemberID: UUID
        var invitations: [FamilyInvitation]
        var transactions: [TransactionItem]
        var pendingFixedExpenses: [FixedExpense]
        var syncQueue: [SyncChange]
        var projects: [ProjectDefinition]
        var budget: BudgetPlan
        var lastSyncText: String
    }

    private static var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("family_ledger.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.storeURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
           !snapshot.members.isEmpty {
            members = snapshot.members
            currentMemberID = snapshot.currentMemberID
            invitations = snapshot.invitations
            transactions = snapshot.transactions
            pendingFixedExpenses = snapshot.pendingFixedExpenses
            syncQueue = snapshot.syncQueue
            projects = snapshot.projects
            budget = snapshot.budget
            lastSyncText = snapshot.lastSyncText
        } else {
            seed()
            save()
        }
    }

    private func save() {
        let snapshot = Snapshot(
            members: members,
            currentMemberID: currentMemberID,
            invitations: invitations,
            transactions: transactions,
            pendingFixedExpenses: pendingFixedExpenses,
            syncQueue: syncQueue,
            projects: projects,
            budget: budget,
            lastSyncText: lastSyncText
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }

    // MARK: - Members

    var currentMember: Member {
        member(currentMemberID) ?? Member(name: "我", initial: "我", color: .teal)
    }

    func member(_ id: UUID) -> Member? {
        members.first { $0.id == id }
    }

    /// 下一個還沒被成員用掉的代表色。
    private var nextAvailableColor: MemberColor {
        let used = Set(members.map(\.color))
        return MemberColor.allCases.first { !used.contains($0) } ?? .grayingFallback
    }

    // MARK: - Invitations

    func invite(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        invitations.insert(FamilyInvitation(inviteeName: trimmed), at: 0)
        save()
    }

    func cancelInvitation(_ id: UUID) {
        invitations.removeAll { $0.id == id }
        save()
    }

    /// Prototype 專用：模擬對方按下「接受邀請」。
    /// 之後接後端時，這個狀態變化會由 server 推回來。
    func simulateAcceptInvitation(_ id: UUID) {
        guard let index = invitations.firstIndex(where: { $0.id == id }) else { return }
        let invitation = invitations[index]
        invitations[index].status = .accepted
        let newMember = Member(
            name: invitation.inviteeName,
            initial: String(invitation.inviteeName.prefix(1)),
            color: nextAvailableColor
        )
        members.append(newMember)
        save()
    }

    /// Prototype 專用：模擬對方婉拒。
    func simulateDeclineInvitation(_ id: UUID) {
        guard let index = invitations.firstIndex(where: { $0.id == id }) else { return }
        invitations[index].status = .declined
        save()
    }

    // MARK: - Transactions

    func addTransaction(_ transaction: TransactionItem, sourceLabel: String) {
        transactions.insert(transaction, at: 0)
        syncQueue.insert(
            SyncChange(kind: .create, title: transaction.title, amount: transaction.amount, source: sourceLabel),
            at: 0
        )
        save()
    }

    func updateTransaction(_ transaction: TransactionItem) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
        syncQueue.insert(
            SyncChange(kind: .update, title: transaction.title, amount: transaction.amount, source: "本機修改"),
            at: 0
        )
        save()
    }

    func deleteTransaction(_ transaction: TransactionItem) {
        transactions.removeAll { $0.id == transaction.id }
        syncQueue.insert(
            SyncChange(kind: .delete, title: transaction.title, amount: transaction.amount, source: "本機刪除"),
            at: 0
        )
        save()
    }

    // MARK: - Fixed Expenses（固定支出確認）

    /// 確認入帳：真的建立一筆交易（原本 prototype 只是把卡片移除）。
    func confirmFixedExpense(_ expense: FixedExpense) {
        let transaction = TransactionItem(
            title: expense.title,
            amount: expense.amount,
            date: .now,
            category: expense.category,
            account: .shared,
            recorderID: currentMemberID,
            tags: [expense.tag],
            repeatSetting: expense.repeatSetting,
            source: .manual
        )
        pendingFixedExpenses.removeAll { $0.id == expense.id }
        addTransaction(transaction, sourceLabel: "固定支出確認")
    }

    /// 這個月跳過：不入帳，但記進待同步佇列（之後對應 POST /recurring-rules/{id}/skip）。
    func skipFixedExpense(_ expense: FixedExpense) {
        pendingFixedExpenses.removeAll { $0.id == expense.id }
        syncQueue.insert(
            SyncChange(kind: .skip, title: expense.title, amount: expense.amount, source: "固定支出跳過"),
            at: 0
        )
        save()
    }

    // MARK: - Sync (mock)

    func sync() {
        guard !isSyncing, !syncQueue.isEmpty else { return }
        isSyncing = true
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            await MainActor.run {
                self.syncQueue.removeAll()
                self.isSyncing = false
                self.lastSyncText = "剛剛已同步"
                self.save()
            }
        }
    }

    // MARK: - Derived: 帳本統計

    /// 共同帳所有交易（全家可見）。
    var sharedTransactions: [TransactionItem] {
        transactions.filter { $0.account == .shared }
    }

    /// 私房帳：只看得到自己的（對齊 spec「其他成員永遠拿不到這些紀錄」）。
    var privateTransactions: [TransactionItem] {
        transactions.filter { $0.account == .privateMoney && $0.recorderID == currentMemberID }
    }

    var sharedTotalThisMonth: Int {
        sharedTransactions.filter { isInCurrentMonth($0.date) }.map(\.amount).reduce(0, +)
    }

    var privateTotalThisMonth: Int {
        privateTransactions.filter { isInCurrentMonth($0.date) }.map(\.amount).reduce(0, +)
    }

    /// 本月共同帳中，某成員記錄的總額。
    func sharedTotalThisMonth(for memberID: UUID) -> Int {
        sharedTransactions
            .filter { $0.recorderID == memberID && isInCurrentMonth($0.date) }
            .map(\.amount)
            .reduce(0, +)
    }

    // MARK: - Derived: 預算

    /// 本月共同帳的分類支出（預算頁用；私房錢不計入家庭預算）。
    var categorySpendingThisMonth: [ExpenseCategory: Int] {
        let thisMonth = sharedTransactions.filter { isInCurrentMonth($0.date) }
        return Dictionary(grouping: thisMonth, by: \.category)
            .mapValues { $0.map(\.amount).reduce(0, +) }
    }

    /// 依今天日期算出的「月進度基準線」（原本寫死 0.62）。
    var dayProgress: Double {
        let day = calendar.component(.day, from: .now)
        let range = calendar.range(of: .day, in: .month, for: .now)?.count ?? 30
        return Double(day) / Double(range)
    }

    // MARK: - Derived: 報表

    /// 近 n 個月的共同帳月支出趨勢（由舊到新）。
    func monthlyTrend(months: Int = 6) -> [(label: String, total: Int)] {
        (0..<months).reversed().compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: .now) else { return nil }
            let comps = calendar.dateComponents([.year, .month], from: monthDate)
            let total = sharedTransactions
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
                .map(\.amount)
                .reduce(0, +)
            return ("\(comps.month ?? 0)月", total)
        }
    }

    /// 本月共同帳的成員分攤（記錄者拆分）。
    func memberSplitThisMonth() -> [(member: Member, total: Int)] {
        members.map { ($0, sharedTotalThisMonth(for: $0.id)) }
    }

    // MARK: - Derived: 專案

    /// 專案底下的交易（tag 符合；私房交易只包含自己的）。
    func projectTransactions(_ project: ProjectDefinition) -> [TransactionItem] {
        (sharedTransactions + privateTransactions).filter { $0.tags.contains(project.tag) }
    }

    func projectSpent(_ project: ProjectDefinition) -> Int {
        projectTransactions(project).map(\.amount).reduce(0, +)
    }

    func projectCount(_ project: ProjectDefinition) -> Int {
        projectTransactions(project).count
    }

    /// 專案的每月長條資料（由舊到新，最多取近 6 個有資料的月份）。
    func projectMonthly(_ project: ProjectDefinition) -> [(label: String, total: Int)] {
        let grouped = Dictionary(grouping: projectTransactions(project)) { tx in
            let comps = calendar.dateComponents([.year, .month], from: tx.date)
            return (comps.year ?? 0) * 100 + (comps.month ?? 0)
        }
        return grouped.keys.sorted().suffix(6).map { key in
            ("\(key % 100)月", grouped[key]?.map(\.amount).reduce(0, +) ?? 0)
        }
    }

    // MARK: - Helpers

    private func isInCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: .now, toGranularity: .month)
    }

    // MARK: - Seed Data

    /// 首次啟動的種子資料。刻意鋪了近 6 個月的歷史交易，
    /// 讓報表趨勢、專案長條圖是真的算出來的，不是寫死的假數字。
    private func seed() {
        let ting = Member(name: "Ting", initial: "婷", color: .orange)
        let kai = Member(name: "Kai", initial: "凱", color: .green)
        members = [ting, kai]
        currentMemberID = ting.id

        let monthlyBabysitter = RepeatSetting(frequency: .monthly, dayOfMonth: 5)
        let monthlyMortgage = RepeatSetting(frequency: .monthly, dayOfMonth: 1)

        var seeded: [TransactionItem] = [
            TransactionItem(title: "超市採買", amount: 1_680, date: daysAgo(0), category: .food, account: .shared, recorderID: ting.id, tags: ["#日常"]),
            TransactionItem(title: "捷運月票", amount: 1_280, date: daysAgo(1), category: .transport, account: .shared, recorderID: kai.id, tags: ["#通勤"]),
            TransactionItem(title: "日本機票訂金", amount: 12_000, date: daysAgo(1), category: .entertainment, account: .shared, recorderID: ting.id, tags: ["#2026日本旅遊"]),
            TransactionItem(title: "驚喜基金存入", amount: 3_000, date: daysAgo(2), category: .other, account: .privateMoney, recorderID: ting.id, tags: ["#surprise"]),
            TransactionItem(title: "買了一杯飲料", amount: 30, date: daysAgo(2), category: .food, account: .shared, recorderID: kai.id, tags: ["#AI", "#語音"], source: .voice),
            TransactionItem(title: "診所掛號", amount: 450, date: daysAgo(3), category: .medical, account: .shared, recorderID: ting.id, tags: ["#小孩"]),
            TransactionItem(title: "外套", amount: 2_490, date: daysAgo(4), category: .clothing, account: .privateMoney, recorderID: kai.id, tags: ["#私房"]),
        ]

        // 近 6 個月的固定支出歷史：保母費（每月 5 日）、房貸（每月 1 日）。
        for monthOffset in 0..<6 {
            seeded.append(TransactionItem(
                title: "保母費", amount: 18_000, date: monthsAgo(monthOffset, day: 5),
                category: .education, account: .shared,
                recorderID: kai.id, tags: ["#保母費"], repeatSetting: monthlyBabysitter
            ))
            seeded.append(TransactionItem(
                title: "房貸", amount: 32_000, date: monthsAgo(monthOffset, day: 1),
                category: .housing, account: .shared,
                recorderID: kai.id, tags: ["#固定支出"], repeatSetting: monthlyMortgage
            ))
        }

        // 日本旅遊專案的歷史支出。
        seeded.append(TransactionItem(title: "日本住宿訂金", amount: 9_800, date: monthsAgo(1, day: 12), category: .entertainment, account: .shared, recorderID: kai.id, tags: ["#2026日本旅遊"]))
        seeded.append(TransactionItem(title: "護照換發", amount: 4_500, date: monthsAgo(2, day: 20), category: .other, account: .shared, recorderID: ting.id, tags: ["#2026日本旅遊"]))
        seeded.append(TransactionItem(title: "行李箱", amount: 8_000, date: monthsAgo(3, day: 8), category: .clothing, account: .shared, recorderID: ting.id, tags: ["#2026日本旅遊"]))

        // 已結案的搬家專案。
        seeded.append(TransactionItem(title: "搬家公司", amount: 22_000, date: monthsAgo(4, day: 15), category: .housing, account: .shared, recorderID: kai.id, tags: ["#搬家"]))
        seeded.append(TransactionItem(title: "新家家具", amount: 18_800, date: monthsAgo(4, day: 22), category: .housing, account: .shared, recorderID: ting.id, tags: ["#搬家"]))
        seeded.append(TransactionItem(title: "家電採買", amount: 18_400, date: monthsAgo(3, day: 2), category: .housing, account: .shared, recorderID: ting.id, tags: ["#搬家"]))

        transactions = seeded.sorted { $0.date > $1.date }

        pendingFixedExpenses = [
            FixedExpense(title: "保母費", amount: 18_000, dueText: "今天到期 · 每月自動入帳", category: .education, tag: "#保母費", repeatSetting: monthlyBabysitter),
            FixedExpense(title: "串流訂閱", amount: 390, dueText: "明天到期", category: .entertainment, tag: "#固定支出", repeatSetting: RepeatSetting(frequency: .monthly, dayOfMonth: 17)),
        ]

        projects = [
            ProjectDefinition(title: "2026 日本旅遊", tag: "#2026日本旅遊", budget: 120_000),
            ProjectDefinition(title: "保母費", tag: "#保母費", budget: 216_000, isFixed: true),
            ProjectDefinition(title: "搬家採買", tag: "#搬家", budget: 60_000, status: .closed),
        ]

        budget = BudgetPlan(
            total: 50_000,
            categoryLimits: [
                .food: 12_000,
                .clothing: 5_000,
                .housing: 32_000,
                .transport: 4_000,
                .education: 20_000,
                .entertainment: 8_000,
                .medical: 5_000,
                .other: 6_000,
            ]
        )

        syncQueue = [
            SyncChange(kind: .create, title: "早餐", amount: 95, source: "離線新增"),
        ]
    }

    private func daysAgo(_ value: Int) -> Date {
        calendar.date(byAdding: .day, value: -value, to: .now) ?? .now
    }

    private func monthsAgo(_ value: Int, day: Int) -> Date {
        guard let base = calendar.date(byAdding: .month, value: -value, to: .now) else { return .now }
        var comps = calendar.dateComponents([.year, .month], from: base)
        comps.day = day
        return calendar.date(from: comps) ?? base
    }
}

private extension MemberColor {
    /// 色盤用完時的保底色。
    static var grayingFallback: MemberColor { .teal }
}
