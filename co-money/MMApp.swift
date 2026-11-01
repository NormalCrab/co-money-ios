import BackgroundTasks
import MMCore
import SwiftUI

@main
struct MMApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    nonisolated static let syncTaskId = "com.codai8.mm.sync"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.accent)
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // 回到前景：換 token、送出待上傳、拉解析結果（§2.2、§3.3）。
                Task { await model.syncNow() }
            case .background:
                Self.scheduleBackgroundSync()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(Self.syncTaskId)) {
            // 系統允許時在背景送出待上傳（§4.4）。
            await model.syncNow()
            Self.scheduleBackgroundSync()
        }
    }

    // .backgroundTask 的 closure 不在主執行緒，BGTaskScheduler 本身可以從任何執行緒呼叫。
    nonisolated static func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: syncTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .starting:
            ProgressView()
        case .loggedOut:
            // 冷啟動時發現登入已過期、但還有待上傳資料：顯示重新登入（§3.3）。
            LoginView(isRelogin: model.needsRelogin)
        case .ready:
            MainTabs()
                .sheet(isPresented: .constant(model.needsRelogin)) {
                    LoginView(isRelogin: true)
                        .interactiveDismissDisabled()
                }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首頁", systemImage: "house") }
            TransactionsView()
                .tabItem { Label("交易", systemImage: "list.bullet") }
            BudgetsView()
                .tabItem { Label("預算", systemImage: "chart.pie") }
            ProfileView()
                .tabItem { Label("我", systemImage: "person") }
        }
    }
}
