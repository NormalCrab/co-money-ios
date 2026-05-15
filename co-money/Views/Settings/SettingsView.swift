// SettingsView.swift
// co-money
// Consolidated settings sheet: profile, invitations, accounts, categories, sign-out.
// 合併設定 Sheet：個人檔案、邀請、帳戶、分類、登出

import SwiftUI

/// SettingsView: 設定檢視
/// Consolidated settings view with multiple sections:
/// 1. Profile display (username, email)
/// 2. Preferences (default currency)
/// 3. Default accounts selection
/// 4. Pending invitations inline + full invitations view
/// 5. Category management (CRUD)
/// 6. Account management
/// 7. Sign out
struct SettingsView: View {
    // MARK: - Environment: Injected view models
    @Environment(ProfileViewModel.self)  private var profileVM
    @Environment(AccountViewModel.self)  private var accountVM
    @Environment(TransactionViewModel.self) private var txVM
    @Environment(AuthViewModel.self)     private var authVM
    @Environment(\.dismiss)             private var dismiss

    // MARK: - Constants: Common currencies for picker
    private let commonCurrencies = ["TWD", "USD", "EUR", "JPY", "CNY", "HKD", "KRW", "GBP", "SGD", "AUD"]

    // ── Category CRUD State ────────────────────────────────────────────────
    // MARK: - Category Management State: 分類新增和刪除狀態 (Category add/delete state)
    @State private var showAddCategory      = false
    @State private var newCatName           = ""
    @State private var newCatIcon           = ""
    @State private var categoryToDelete: Category?
    @State private var showDeleteCatConfirm = false

    // ── Invitations State ──────────────────────────────────────────────────
    // MARK: - Invitations State: 邀請載入和顯示狀態 (Invitations loading/display state)
    @State private var received:     [Invitation] = []
    @State private var invLoading    = false
    @State private var showInviteAll = false   // full InvitationsView sheet

    private let invService = AccountService.shared

    var body: some View {
        NavigationStack {
            List {
                // MARK: Sections: 設定各個部分 (Settings sections)
                profileSection
                preferencesSection
                defaultAccountsSection
                invitationsSection
                categoriesSection
                accountManagementSection
                signOutSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: Close Button: 關閉設定檢視 (Close settings view)
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            // MARK: Add Category Alert: 新增分類對話框 (Alert for adding category)
            .alert("新增分類", isPresented: $showAddCategory) {
                TextField("分類名稱", text: $newCatName).autocorrectionDisabled()
                TextField("Emoji 圖示（選填）", text: $newCatIcon)
                Button("新增") {
                    let name = newCatName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        Task {
                            await profileVM.createCategory(
                                name: name,
                                icon: newCatIcon.isEmpty ? nil : newCatIcon
                            )
                        }
                    }
                    newCatName = ""; newCatIcon = ""
                }
                Button("取消", role: .cancel) { newCatName = ""; newCatIcon = "" }
            }
            // MARK: Delete Category Confirmation: 刪除分類確認對話框 (Confirm delete category)
            .confirmationDialog(
                "確定刪除分類「\(categoryToDelete?.name ?? "")」？",
                isPresented: $showDeleteCatConfirm,
                titleVisibility: .visible
            ) {
                Button("刪除", role: .destructive) {
                    if let cat = categoryToDelete {
                        Task { await profileVM.deleteCategory(id: cat.id) }
                    }
                }
                Button("取消", role: .cancel) {}
            }
            // MARK: Error Alert: 顯示錯誤訊息 (Show error messages)
            .alert("錯誤", isPresented: .constant(profileVM.errorMessage != nil)) {
                Button("確定") { profileVM.errorMessage = nil }
            } message: {
                Text(profileVM.errorMessage ?? "")
            }
            // MARK: Full Invitations Sheet: 完整邀請管理檢視 (Full invitations management view)
            .sheet(isPresented: $showInviteAll) {
                NavigationStack {
                    InvitationsView()
                        .environment(accountVM)
                }
            }
        }
        // MARK: Initial Load: 載入待處理邀請 (Load pending invitations)
        .task {
            await loadInvitations()
        }
    }

    // MARK: - Profile Section
    /// 顯示使用者個人檔案（用戶名、郵件） (Display user profile)
    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                // MARK: Avatar: 用戶名首字母頭像 (Avatar with first letter)
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Text(String(profileVM.username.prefix(1)).uppercased())
                        .font(.title2.bold())
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(profileVM.username)
                        .font(.title3.bold())
                    if let email = profileVM.profile?.user.email, !email.isEmpty {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Preferences Section
    /// 顯示偏好設定如預設貨幣 (Show preferences like default currency)
    private var preferencesSection: some View {
        Section("偏好設定") {
            let currentCurrency = profileVM.profile?.defaultCurrency ?? commonCurrencies[0]
            // MARK: Currency Picker: 選擇預設貨幣 (Select default currency)
            Picker(selection: Binding(
                get: { currentCurrency },
                set: { newVal in Task { await profileVM.updateDefaultCurrency(newVal) } }
            )) {
                ForEach(commonCurrencies, id: \.self) { cur in
                    Text(cur).tag(cur)
                }
            } label: {
                Label("預設貨幣", systemImage: "banknote")
            }
        }
    }

    // MARK: - Default Accounts Section
    /// 選擇在新交易中預設使用的帳戶 (Select default accounts for new transactions)
    private var defaultAccountsSection: some View {
        Section("預設帳戶") {
            if accountVM.accounts.isEmpty {
                Text("尚未建立任何帳戶").foregroundStyle(.secondary).font(.subheadline)
            } else {
                let defaultIds = profileVM.profile?.defaultSharedAccounts ?? []
                ForEach(accountVM.accounts) { acc in
                    HStack {
                        // MARK: Checkmark: 已選中的帳戶顯示勾選 (Selected accounts show checkmark)
                        Image(systemName: defaultIds.contains(acc.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(defaultIds.contains(acc.id) ? Color.accentColor : .secondary)
                        Text(acc.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var ids = defaultIds
                        if ids.contains(acc.id) { ids.removeAll { $0 == acc.id } }
                        else { ids.append(acc.id) }
                        Task { await profileVM.updateDefaultAccounts(ids) }
                    }
                }
            }
        }
    }

    // MARK: - Invitations Section (Pending + Full View Link)
    /// 顯示待處理邀請和全部邀請連結 (Show pending invitations and full view link)
    private var invitationsSection: some View {
        Section {
            if invLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if received.isEmpty {
                HStack {
                    Text("沒有待處理邀請")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                // MARK: Pending Invitations: 顯示待處理的邀請 (Show pending invitations)
                ForEach(received) { inv in
                    InlinePendingInvitationRow(
                        invitation: inv,
                        accounts:   accountVM.accounts
                    ) {
                        Task { await acceptInv(inv) }
                    } onDecline: {
                        Task { await declineInv(inv) }
                    }
                }
            }

            // MARK: View All Link: 連結到完整邀請檢視 (Link to full invitations view)
            Button {
                showInviteAll = true
            } label: {
                Label("查看全部邀請", systemImage: "envelope.badge")
                    .font(.subheadline)
            }
        } header: {
            HStack {
                Text("邀請")
                if !received.isEmpty {
                    // MARK: Badge: 待處理邀請計數 (Badge showing pending count)
                    Text("\(received.count)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Categories Section
    /// 管理交易分類（建立、刪除） (Manage transaction categories)
    private var categoriesSection: some View {
        Section {
            if profileVM.categories.isEmpty {
                Text("尚無分類").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(profileVM.categories) { cat in
                    HStack(spacing: 10) {
                        // MARK: Category Icon: 顯示分類圖示或圖標 (Show category emoji or icon)
                        if let icon = cat.icon, !icon.isEmpty {
                            Text(icon).font(.title3).frame(width: 28)
                        } else {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(Color.accentColor).frame(width: 28)
                        }
                        Text(cat.name)
                    }
                }
                // MARK: Delete Gesture: 下滑刪除分類 (Swipe to delete category)
                .onDelete { indices in
                    for i in indices {
                        categoryToDelete = profileVM.categories[i]
                        showDeleteCatConfirm = true
                    }
                }
            }
        } header: {
            HStack {
                Text("分類")
                Spacer()
                // MARK: Add Button: 新增分類 (Add category)
                Button { showAddCategory = true } label: {
                    Image(systemName: "plus")
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Account Management Section
    /// 導航到帳戶管理檢視 (Navigate to account management)
    private var accountManagementSection: some View {
        Section("帳戶管理") {
            NavigationLink {
                AccountListView()
                    .environment(accountVM)
                    .environment(txVM)
                    .environment(profileVM)
            } label: {
                Label("共享帳戶", systemImage: "person.2.fill")
            }
        }
    }

    // MARK: - Sign Out Section
    /// 登出帳戶 (Sign out from account)
    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                // Dismiss the sheet first, then logout.
                // This prevents SwiftUI from getting stuck trying to both close
                // the sheet and transition the root view simultaneously.
                // 先關閉 sheet，再執行登出，避免 SwiftUI 同時要做兩件事而卡住。
                dismiss()
                Task { await authVM.logout() }
            } label: {
                Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Invitation Helper Functions

    /// Load pending invitations
    /// 載入待處理邀請 (Load pending invitations)
    private func loadInvitations() async {
        invLoading = true
        if let list = try? await invService.getMyInvitations() {
            received = list.filter { $0.status == .pending || $0.status == nil }
        }
        invLoading = false
    }

    /// Accept an invitation
    /// 接受邀請 (Accept invitation)
    private func acceptInv(_ inv: Invitation) async {
        try? await invService.acceptInvitation(id: inv.id)
        received.removeAll { $0.id == inv.id }
        await accountVM.loadAccounts()
        accountVM.pendingInvitationCount = received.count
    }

    /// Decline an invitation
    /// 拒絕邀請 (Decline invitation)
    private func declineInv(_ inv: Invitation) async {
        try? await invService.declineInvitation(id: inv.id)
        received.removeAll { $0.id == inv.id }
        accountVM.pendingInvitationCount = received.count
    }
}

// MARK: - Inline Pending Invitation Row
/// 在設定中內嵌顯示的待處理邀請列 (Inline pending invitation row in settings)
struct InlinePendingInvitationRow: View {
    let invitation: Invitation
    let accounts:   [SharedAccount]
    let onAccept:  () -> Void
    let onDecline: () -> Void

    /// Resolve account UUID to display name
    /// 解析帳戶 UUID 為顯示名稱 (Resolve account ID to name)
    private var accountName: String {
        accounts.first(where: { $0.id == invitation.account })?.name
            ?? "帳戶 \(invitation.account.prefix(8))…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // MARK: Icon: 邀請圖示 (Invitation icon)
                Image(systemName: "envelope.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(accountName).font(.subheadline.bold())
                    if let inviter = invitation.inviter {
                        // MARK: Inviter Info: 顯示邀請者資訊 (Show inviter info)
                        Text("來自 \(inviter.username)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // MARK: Date: 邀請日期 (Invitation date)
                Text(invitation.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                // MARK: Accept Button: 接受邀請 (Accept invitation)
                Button(action: onAccept) {
                    Text("接受")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)

                // MARK: Decline Button: 拒絕邀請 (Decline invitation)
                Button(action: onDecline) {
                    Text("拒絕")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
