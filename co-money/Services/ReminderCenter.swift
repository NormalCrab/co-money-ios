import MMCore
import UserNotifications

/// 提醒記帳的本機通知（不需要後端，也不需要 APNs）：權限、排程、使用者點了通知之後打開「記一筆」。
///
/// 每天一則、不重複的通知，一次排好接下來的幾天（`ReminderPlanner`），記了一筆就重排、跳過今天。
/// delegate 的方法由系統在背景執行緒呼叫，所以標成 nonisolated，再切回主執行緒（CLAUDE.md 的 Swift 6 執行緒檢查）。
@MainActor
final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let categoryId = "reminder"
    nonisolated static let quickEntryAction = "quick-entry"
    private nonisolated static let idPrefix = "reminder-"

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

    /// 取消舊的提醒，照 `days` 重新排。時間不帶時區：出國時在當地的同一個時間提醒。
    func schedule(days: [LocalDate], hour: Int, minute: Int) async {
        await cancelAll()
        for day in days {
            let content = UNMutableNotificationContent()
            content.title = "記帳提醒"
            content.body = "今天的花費記了嗎？花 10 秒記一下。"
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            let when = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
            let request = UNNotificationRequest(
                identifier: Self.idPrefix + day.description, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// app 開著時不跳出提醒：人已經在 app 裡了。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == Self.categoryId else { return }
        await MainActor.run { self.onQuickEntry?() }
    }
}
