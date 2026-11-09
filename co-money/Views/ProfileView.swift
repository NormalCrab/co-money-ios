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
                notificationsDenied = model.reminderSettings.isEnabled && isDenied
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

/// 提醒記帳：開關、時間、星期。打開時才詢問通知權限（預設關閉，比較不會被直接拒絕）。
private struct ReminderSection: View {
    @Environment(AppModel.self) private var model
    @Binding var denied: Bool

    private static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]  // ISO：1 是週一

    private var settings: ReminderSettings { model.reminderSettings }

    var body: some View {
        Section {
            Toggle("提醒記帳", isOn: Binding(get: { settings.isEnabled }, set: { on in Task { await setEnabled(on) } }))
            if settings.isEnabled {
                DatePicker("時間", selection: timeBinding, displayedComponents: .hourAndMinute)
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        weekdayButton(day)
                    }
                }
                .padding(.vertical, 2)
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
            Text("到了設定的時間，今天還沒記帳就提醒你；今天已經記過就不提醒。")
        }
    }

    private func weekdayButton(_ day: Int) -> some View {
        let isOn = settings.weekdays.contains(day)
        return Button {
            var updated = settings
            if isOn {
                guard updated.weekdays.count > 1 else { return }  // 至少留一天，全關請用上面的開關
                updated.weekdays.remove(day)
            } else {
                updated.weekdays.insert(day)
            }
            Task { await model.updateReminderSettings(updated) }
        } label: {
            Text(Self.weekdayNames[day - 1])
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(isOn ? Palette.accentText : .secondary)
                .background(isOn ? Palette.accentSoft : Color.clear, in: Circle())
                .overlay(Circle().stroke(isOn ? Palette.accent : Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("週\(Self.weekdayNames[day - 1])")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updated = settings
                updated.hour = parts.hour ?? updated.hour
                updated.minute = parts.minute ?? updated.minute
                Task { await model.updateReminderSettings(updated) }
            })
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
        var updated = settings
        updated.isEnabled = on
        await model.updateReminderSettings(updated)
    }
}
