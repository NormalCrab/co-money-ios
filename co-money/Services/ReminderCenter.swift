import UserNotifications

/// 提醒記帳的本機通知（不需要後端，也不需要 APNs）：每天中午 12 點、下午 3 點、傍晚 6 點、晚上 9 點各一則，問有沒有花費，點了打開「記一筆」。
/// 不管今天記過沒有都會提醒，app 開著時也照樣跳出（Alex 2026-11-10）。
///
/// 用每天重複的通知，排一次就一直有效，app 很久沒打開也照樣提醒。
/// delegate 的方法由系統在背景執行緒呼叫，所以標成 nonisolated，再切回主執行緒（CLAUDE.md 的 Swift 6 執行緒檢查）。
@MainActor
final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let categoryId = "reminder"
    nonisolated static let quickEntryAction = "quick-entry"
    private nonisolated static let idPrefix = "reminder-"

    /// 每天的提醒：每三個小時問一次這段時間有沒有花費。
    private nonisolated static let daily: [(hour: Int, body: String)] = [
        (12, "早上到中午有花費嗎？有的話花 10 秒記一下。"),
        (15, "中午到下午有花費嗎？有的話花 10 秒記一下。"),
        (18, "下午到傍晚有花費嗎？有的話花 10 秒記一下。"),
        (21, "晚上有花費嗎？有的話花 10 秒記一下。"),
    ]

    /// 使用者點了提醒（本身或上面的「記一筆」）。
    var onQuickEntry: (() -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        let action = UNNotificationAction(identifier: Self.quickEntryAction, title: "記一筆", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryId, actions: [action], intentIdentifiers: []),
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

    private nonisolated static var ids: [String] { daily.map { "\(idPrefix)\($0.hour)" } }

    /// 排好每天的提醒。同一個 id 會蓋掉舊的，重複呼叫也只會有這兩則。時間不帶時區：出國時在當地的同一個時間提醒。
    ///
    /// 排和取消都不等系統回應（沒有 await）：呼叫端判斷完就馬上送出，中間不會被另一次呼叫插隊。
    /// 以前先 await 查目前排了哪些再刪，兩次呼叫交錯時，晚到的刪除會把剛排好的提醒刪掉。
    func scheduleDaily() {
        for reminder in Self.daily {
            let content = UNMutableNotificationContent()
            content.title = "有花費嗎？"
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            let request = UNNotificationRequest(
                identifier: "\(Self.idPrefix)\(reminder.hour)", content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: reminder.hour, minute: 0),
                                                       repeats: true))
            center.add(request, withCompletionHandler: nil)
        }
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: Self.ids)
    }

    /// 下一次提醒的時間；沒有排好提醒時是 nil。「我」頁面顯示，讓人確認提醒真的排好了。
    func nextReminderDate() async -> Date? {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.idPrefix) }
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .min()
    }

    // MARK: UNUserNotificationCenterDelegate

    /// app 開著時也跳出提醒（不管如何都提醒），點了一樣打開「記一筆」。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == Self.categoryId else { return }
        await MainActor.run { self.onQuickEntry?() }
    }
}
