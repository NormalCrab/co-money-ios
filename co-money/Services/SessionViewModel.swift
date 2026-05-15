// SessionViewModel.swift
// co-money
// Drives login state and root view switching in SwiftUI (Plan A)

import Foundation
import Combine

extension Notification.Name {
    /// Posted when the user changes the globally selected month (year/month) so all pages can refresh consistently.
    static let selectedMonthDidChange = Notification.Name("selectedMonthDidChange")

    /// Posted to instruct all screens/view models to refresh their data for the currently selected month (force remote fetch, avoid cache).
    static let dataShouldRefreshForSelectedMonth = Notification.Name("dataShouldRefreshForSelectedMonth")

    /// Posted right after a successful login so UI can refresh fresh data (e.g., current month) from API.
    static let sessionDidLoginNeedsRefresh = Notification.Name("sessionDidLoginNeedsRefresh")
}

/// A single source of truth for the user's session state.
/// Owns the `isLoggedIn` flag and wraps KeychainService reads/writes.
final class SessionViewModel: ObservableObject {
    /// Whether the user is currently authenticated.
    /// This mirrors KeychainService.shared.isLoggedIn and drives the root UI.
    @Published var isLoggedIn: Bool

    /// Globally selected month (year/month). All pages should use this to show consistent data.
    @Published var selectedMonth: DateComponents

    /// Optional: expose read-only tokens if needed by views/clients.
    var accessToken: String? { KeychainService.shared.accessToken }
    var refreshToken: String? { KeychainService.shared.refreshToken }

    init() {
        // Initialize from Keychain so the state survives app relaunches.
        self.isLoggedIn = KeychainService.shared.isLoggedIn
        // Default selected month = current month (year/month only)
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: now)
        self.selectedMonth = comps
    }

    /// Update the globally selected month (year/month) and notify subscribers to refresh.
    func setSelectedMonth(year: Int, month: Int) {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        // Only update if changed to avoid redundant refreshes
        if comps.year != selectedMonth.year || comps.month != selectedMonth.month {
            selectedMonth = comps
            DispatchQueue.main.async {
                let info: [String: Any] = [
                    "year": year,
                    "month": month
                ]
                NotificationCenter.default.post(name: .selectedMonthDidChange, object: nil, userInfo: info)
                NotificationCenter.default.post(name: .dataShouldRefreshForSelectedMonth, object: nil, userInfo: info)
            }
        }
    }

    /// Broadcast a refresh event for the current selected month. Useful when you need to re-sync all pages without changing the month (e.g., after settings change).
    func broadcastRefreshForSelectedMonth() {
        let year = selectedMonth.year ?? Calendar.current.component(.year, from: Date())
        let month = selectedMonth.month ?? Calendar.current.component(.month, from: Date())
        DispatchQueue.main.async {
            let info: [String: Any] = [
                "year": year,
                "month": month
            ]
            NotificationCenter.default.post(name: .dataShouldRefreshForSelectedMonth, object: nil, userInfo: info)
        }
    }

    /// Call after a successful sign-in to persist tokens and enter the app.
    func didLogin(accessToken: String, refreshToken: String, username: String? = nil) {
        KeychainService.shared.accessToken = accessToken
        KeychainService.shared.refreshToken = refreshToken
        if let username { KeychainService.shared.username = username }
        // Update session state (on main to drive UI updates) and notify UI to refresh fresh data
        DispatchQueue.main.async { [weak self] in
            self?.isLoggedIn = true
            NotificationCenter.default.post(name: .sessionDidLoginNeedsRefresh, object: nil)
        }
    }

    /// Call when the user explicitly logs out.
    func logout() {
        KeychainService.shared.clearTokens()
        DispatchQueue.main.async { [weak self] in
            self?.isLoggedIn = false
        }
    }

    /// Call when the backend responds with 401 Unauthorized.
    /// This should clear sensitive data and return user to Sign-In.
    func handleUnauthorized() {
        KeychainService.shared.clearTokens()
        DispatchQueue.main.async { [weak self] in
            self?.isLoggedIn = false
        }
    }
}

// MARK: - SwiftUI integration (reference)
// In your App entry point, inject as an EnvironmentObject and switch root views:
//
// @main
// struct CoMoneyApp: App {
//     @StateObject private var session = SessionViewModel()
//
//     var body: some Scene {
//         WindowGroup {
//             Group {
//                 if session.isLoggedIn {
//                     MainTabView() // your main content
//                 } else {
//                     SignInView()
//                 }
//             }
//             .environmentObject(session)
//         }
//     }
// }
//
// In your networking layer, when you detect 401, call:
// DispatchQueue.main.async {
//     session.handleUnauthorized()
// }
// (You can pass the session via EnvironmentObject to views, or inject it into services.)

