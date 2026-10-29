import Foundation
import Network

/// 網路狀態（ios-design §4.4：網路恢復時送出待上傳）。
@MainActor
@Observable
final class Connectivity {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    /// 網路從斷線變成連線時呼叫。
    var onReconnect: (() -> Void)?

    func start() {
        // @Sendable：在 monitor 的 queue 上被呼叫，不能被推斷成只能在主執行緒跑。
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline { self.onReconnect?() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity"))
    }
}
