import MMCore
import SwiftUI

/// 「我」：帳號、伺服器、登出。
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmLogout = false
    @State private var invitationCount = 0

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
                        NavigationLink("重複交易") { RecurringRulesView() }
                    }
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
            .task { invitationCount = (try? await model.api.myInvitations().count) ?? 0 }
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
