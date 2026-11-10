import MMCore
import SwiftUI

/// 「我」：帳號、設定、提醒記帳、伺服器、登出。
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmLogout = false
    @State private var invitationCount = 0
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfflineBanner()
                Form {
                    Section("帳號") {
                        LabeledContent("使用者", value: model.username)
                        LabeledContent("目前帳本", value: model.selectedLedger?.name ?? "—")
                    }
                    Section("設定") {
                        // 出國時常用，放在最上面，不用從「帳本」一層層點進去。
                        if let ledger = model.selectedLedger {
                            NavigationLink {
                                ExchangeRatesView(ledger: ledger)
                            } label: {
                                LabeledContent("匯率", value: ledger.name)
                            }
                        }
                        NavigationLink("帳本") { LedgersView() }
                        NavigationLink {
                            InvitationsView()
                        } label: {
                            HStack {
                                Text("收到的邀請")
                                Spacer()
                                if invitationCount > 0 {
                                    Text("\(invitationCount)").font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Palette.accentSoft, in: Capsule())
                                        .foregroundStyle(Palette.accentText)
                                }
                            }
                        }
                        NavigationLink("固定收支") { RecurringRulesView() }
                    }
                    ReminderSection(denied: $notificationsDenied)
                    Section {
                        Picker("伺服器", selection: Binding(
                            get: { model.server },
                            set: { server in Task { await model.switchServer(to: server) } }
                        )) {
                            ForEach(Server.allCases) { Text($0.label).tag($0) }
                        }
                    } footer: {
                        Text("兩邊的登入和待上傳資料分開保存。")
                    }
                    Section {
                        Button("登出", role: .destructive) { confirmLogout = true }
                    }
                }
            }
            .navigationTitle("我")
            .task {
                // 使用者可能在「設定」裡把通知關掉了：開著提醒卻收不到時要說明。
                let isDenied = await model.reminders.isDenied
                notificationsDenied = model.remindersEnabled && isDenied
                invitationCount = (try? await model.api.myInvitations().count) ?? 0
            }
            .confirmationDialog(logoutMessage, isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("登出", role: .destructive) { Task { await model.logout() } }
            }
        }
    }

    /// 有待上傳資料時要先警告（§3.3）。
    private var logoutMessage: String {
        model.hasUnsentData
            ? "還有 \(model.outboxItems.count) 筆資料沒有上傳。登出後要用同一個帳號登入才會送出。"
            : "確定要登出嗎？"
    }
}

/// 提醒記帳：每天下午 3 點、晚上 9 點，點通知直接打開「記一筆」。
/// 打開時才詢問通知權限（預設關閉，比較不會被直接拒絕）。
private struct ReminderSection: View {
    @Environment(AppModel.self) private var model
    @Binding var denied: Bool
    /// 系統裡實際排好的下一次提醒，讓人確認提醒真的排好了。
    @State private var next: Date?

    var body: some View {
        Section {
            Toggle("提醒記帳", isOn: Binding(get: { model.remindersEnabled },
                                         set: { on in Task { await setEnabled(on) } }))
            if model.remindersEnabled && !denied {
                LabeledContent("下一次提醒", value: next.map(Self.describe) ?? "還沒排好")
            }
            if denied {
                Text("通知權限被關掉了，收不到提醒。").font(.footnote).foregroundStyle(Palette.warning)
                Button("開啟設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote)
            }
        } header: {
            Text("提醒")
        } footer: {
            Text("每天下午 3 點和晚上 9 點提醒你記帳，點通知就能直接記一筆。")
        }
        .task { await loadNext() }
    }

    private func setEnabled(_ on: Bool) async {
        if on {
            // 之前拒絕過的話不會再跳出詢問，直接回傳 false：說明要到「設定」打開。
            guard await model.reminders.requestAuthorization() else {
                denied = true
                return
            }
        }
        denied = false
        await model.setRemindersEnabled(on)
        await loadNext()
    }

    private func loadNext() async {
        // 剛送出的排程系統要一下子才查得到。
        try? await Task.sleep(for: .milliseconds(300))
        next = await model.reminders.nextReminderDate()
    }

    /// 「今天 21:00」「明天 15:00」。通知用手機的時間，不是帳本時區。
    private static func describe(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInTomorrow(date) { return "明天 \(time)" }
        return date.formatted(.dateTime.month(.defaultDigits).day()) + " " + time
    }
}
