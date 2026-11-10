import UserNotifications

/// 記帳入口：首頁的三個按鈕，也是提醒通知上的三個按鈕。
enum EntryKind: String, Identifiable, Sendable, CaseIterable {
    case form, voice, receipt
    var id: String { rawValue }

    var title: String {
        switch self {
        case .form: "記一筆"
        case .voice: "語音"
        case .receipt: "拍收據"
        }
    }

    /// SF Symbols 的圖示（首頁按鈕和通知按鈕共用）。
    var symbol: String {
        switch self {
        case .form: "plus"
        case .voice: "mic"
        case .receipt: "doc.viewfinder"
        }
    }

    /// 通知按鈕的 id。
    var actionId: String { "entry-\(rawValue)" }
}

/// 提醒記帳的本機通知（不需要後端，也不需要 APNs）：每天中午 12 點、下午 3 點、傍晚 6 點、晚上 9 點各一則，問有沒有花費。
/// 不管今天記過沒有都會提醒，app 開著時也照樣跳出（Alex 2026-11-10）。
///
/// 點通知打開「記一筆」；長按（或往下拉）通知會出現「記一筆」「語音」「拍收據」三個按鈕，點了直接打開那個畫面。
/// 測試模式（只影響這支手機）改成每 10 分鐘一則，方便試通知。
///
/// 用重複的通知，排一次就一直有效，app 很久沒打開也照樣提醒。
/// delegate 的方法由系統在背景執行緒呼叫，所以標成 nonisolated，再切回主執行緒（CLAUDE.md 的 Swift 6 執行緒檢查）。
@MainActor
final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let categoryId = "reminder"
    private nonisolated static let idPrefix = "reminder-"

    /// 每天的提醒：每三個小時問一次這段時間有沒有花費。
    private nonisolated static let daily: [(hour: Int, body: String)] = [
        (12, "早上到中午有花費嗎？有的話花 10 秒記一下。"),
        (15, "中午到下午有花費嗎？有的話花 10 秒記一下。"),
        (18, "下午到傍晚有花費嗎？有的話花 10 秒記一下。"),
        (21, "晚上有花費嗎？有的話花 10 秒記一下。"),
    ]

    /// 測試模式：每小時的 0、10、20…50 分各一則，等於每 10 分鐘一次。
    private nonisolated static let testMinutes = Array(stride(from: 0, to: 60, by: 10))

    private nonisolated static var dailyIds: [String] { daily.map { "\(idPrefix)\($0.hour)" } }
    private nonisolated static var testIds: [String] { testMinutes.map { "\(idPrefix)test-\($0)" } }

    /// 使用者點了提醒：本身是「記一筆」，或通知上的其中一個按鈕。
    var onEntry: ((EntryKind) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        let actions = EntryKind.allCases.map { kind in
            UNNotificationAction(identifier: kind.actionId, title: kind.title, options: [.foreground],
                                 icon: UNNotificationActionIcon(systemImageName: kind.symbol))
        }
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryId, actions: actions, intentIdentifiers: []),
        ])
        // 要在 app 啟動時就設好，點通知冷啟動 app 時才收得到。
        center.delegate = self
    }

    /// 第一次會跳出系統的詢問；之前拒絕過就直接回傳 false（要到「設定」打開）。
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    var isDenied: Bool {
        get async { await center.notificationSettings().authorizationStatus == .denied }
    }

    /// 還沒問過通知權限。
    var isNotDetermined: Bool {
        get async { await center.notificationSettings().authorizationStatus == .notDetermined }
    }

    /// 排好提醒：平常是每天四個時間，測試模式是每 10 分鐘。同一個 id 會蓋掉舊的，另一種模式的會取消。
    /// 時間不帶時區：出國時在當地的同一個時間提醒。
    ///
    /// 排和取消都不等系統回應（沒有 await）：呼叫端判斷完就馬上送出，中間不會被另一次呼叫插隊。
    /// 以前先 await 查目前排了哪些再刪，兩次呼叫交錯時，晚到的刪除會把剛排好的提醒刪掉。
    func schedule(testMode: Bool) {
        if testMode {
            center.removePendingNotificationRequests(withIdentifiers: Self.dailyIds)
            for (minute, id) in zip(Self.testMinutes, Self.testIds) {
                add(id: id, body: "有花費的話花 10 秒記一下。", at: DateComponents(minute: minute))
            }
        } else {
            center.removePendingNotificationRequests(withIdentifiers: Self.testIds)
            for (reminder, id) in zip(Self.daily, Self.dailyIds) {
                add(id: id, body: reminder.body, at: DateComponents(hour: reminder.hour, minute: 0))
            }
        }
    }

    private func add(id: String, body: String, at time: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = "有花費嗎？"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: Self.dailyIds + Self.testIds)
    }

    /// 下一次提醒的時間；沒有排好提醒時是 nil。「我」頁面顯示，讓人確認提醒真的排好了。
    func nextReminderDate() async -> Date? {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.idPrefix) }
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .min()
    }

    // MARK: UNUserNotificationCenterDelegate

    /// app 開著時也跳出提醒（不管如何都提醒），按鈕一樣可以用。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == Self.categoryId else { return }
        // 點通知本身（不是按鈕）打開「記一筆」。
        let kind = EntryKind.allCases.first { $0.actionId == response.actionIdentifier } ?? .form
        await MainActor.run { self.onEntry?(kind) }
    }
}
