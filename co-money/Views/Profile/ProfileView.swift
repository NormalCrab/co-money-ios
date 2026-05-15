// ProfileView.swift
// co-money

import SwiftUI

/// ProfileView: 個人檔案檢視
/// Displays user profile with sections for:
/// 1. User info (username, email)
/// 2. Preferences (default currency)
/// 3. Default accounts selection
/// 4. Category management
/// 5. Account and invitation management
/// 6. Sign out
struct ProfileView: View {
    // MARK: - Environment: Injected view models
    @Environment(ProfileViewModel.self)  private var vm
    @Environment(AccountViewModel.self)  private var accountVM
    @Environment(AuthViewModel.self)     private var authVM

    // MARK: - Currency Alert State: 貨幣設定對話框狀態 (Currency alert state)
    @State private var showCurrencyAlert = false
    @State private var newCurrency       = ""

    // MARK: - Category Management State: 分類管理狀態 (Category management state)
    @State private var showAddCategory   = false
    @State private var newCatName        = ""
    @State private var newCatIcon        = ""
    @State private var categoryToDelete: Category?
    @State private var showDeleteCatConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                // MARK: Loading State: 初始載入時顯示進度 (Show progress during initial load)
                if vm.isLoading && vm.profile == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // MARK: Profile List: 個人檔案各部分 (Profile sections)
                    List {
                        userSection
                        preferencesSection
                        defaultAccountsSection
                        categoriesSection
                        invitationsSection
                        signOutSection
                    }
                }
            }
            .navigationTitle("個人 Profile")
            // MARK: Pull-to-Refresh: 下拉重新載入個人檔案 (Pull to refresh profile)
            .refreshable { await vm.loadProfile() }
            // MARK: Currency Alert: 設定預設貨幣對話框 (Alert for setting default currency)
            .alert("設定預設貨幣", isPresented: $showCurrencyAlert) {
                TextField("例: TWD / USD / EUR", text: $newCurrency)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button("儲存") {
                    let val = newCurrency.uppercased().trimmingCharacters(in: .whitespaces)
                    if !val.isEmpty { Task { await vm.updateDefaultCurrency(val) } }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("輸入 3 位幣種代碼（如 TWD、USD、EUR）")
            }
            // MARK: Add Category Alert: 新增分類對話框 (Alert for adding category)
            .alert("新增分類", isPresented: $showAddCategory) {
                TextField("分類名稱 Name", text: $newCatName)
                    .autocorrectionDisabled()
                TextField("圖示 Emoji（選填）", text: $newCatIcon)
                Button("新增") {
                    let name = newCatName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        Task {
                            await vm.createCategory(
                                name: name,
                                icon: newCatIcon.isEmpty ? nil : newCatIcon
                            )
                        }
                    }
                    newCatName = ""
                    newCatIcon = ""
                }
                Button("取消", role: .cancel) {
                    newCatName = ""
                    newCatIcon = ""
                }
            } message: {
                Text("輸入分類名稱及選填 Emoji 圖示")
            }
            // MARK: Confirm Delete Category: 刪除分類確認對話框 (Confirm delete category)
            .confirmationDialog(
                "確定刪除分類「\(categoryToDelete?.name ?? "")」？",
                isPresented: $showDeleteCatConfirm,
                titleVisibility: .visible
            ) {
                Button("刪除", role: .destructive) {
                    if let cat = categoryToDelete {
                        Task { await vm.deleteCategory(id: cat.id) }
                    }
                }
                Button("取消", role: .cancel) {}
            }
            // MARK: Error Alert: 顯示錯誤訊息 (Show error messages)
            .alert("錯誤", isPresented: .constant(vm.errorMessage != nil)) {
                Button("確定") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - User Section
    /// 顯示使用者基本資訊（用戶名、郵件）
    /// Show basic user info (username, email)
    private var userSection: some View {
        Section {
            HStack(spacing: 16) {
                // MARK: Avatar: 使用預設圖示代替頭像 (Use default icon for avatar)
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.username)
                        .font(.title3.bold())
                    if let email = vm.profile?.user.email, !email.isEmpty {
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
    /// 顯示使用者偏好設定（預設貨幣）
    /// Show user preferences (default currency)
    private var preferencesSection: some View {
        Section("偏好設定 Preferences") {
            HStack {
                Label("預設貨幣", systemImage: "banknote")
                Spacer()
                // MARK: Currency Display: 顯示當前預設貨幣 (Show current default currency)
                Text(vm.profile?.defaultCurrency ?? "未設定")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            // MARK: Tap to Edit: 點擊編輯貨幣 (Tap to edit currency)
            .onTapGesture {
                newCurrency = vm.profile?.defaultCurrency ?? ""
                showCurrencyAlert = true
            }
        }
    }

    // MARK: - Default Accounts Section
    /// 選擇在新交易中預設使用的帳戶
    /// Select default accounts for new transactions
    private var defaultAccountsSection: some View {
        Section("預設帳戶 Default Accounts") {
            if accountVM.accounts.isEmpty {
                Text("尚未建立任何帳戶")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                let defaultIds = vm.profile?.defaultSharedAccounts ?? []
                ForEach(accountVM.accounts) { acc in
                    HStack {
                        // MARK: Checkmark: 已選帳戶顯示勾選 (Selected accounts show checkmark)
                        Image(systemName: defaultIds.contains(acc.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(defaultIds.contains(acc.id) ? Color.accentColor : .secondary)
                        Text(acc.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var ids = defaultIds
                        if ids.contains(acc.id) {
                            ids.removeAll { $0 == acc.id }
                        } else {
                            ids.append(acc.id)
                        }
                        Task { await vm.updateDefaultAccounts(ids) }
                    }
                }
            }
        }
    }

    // MARK: - Categories Section
    /// 管理交易分類（建立、查看、刪除）
    /// Manage transaction categories (create, view, delete)
    private var categoriesSection: some View {
        Section {
            if vm.categories.isEmpty {
                Text("尚無分類，點擊右方 + 新增")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(vm.categories) { cat in
                    HStack(spacing: 10) {
                        // MARK: Category Icon: 顯示分類圖示或標籤圖標 (Show emoji or tag icon)
                        if let icon = cat.icon, !icon.isEmpty {
                            Text(icon)
                                .font(.title3)
                                .frame(width: 28)
                        } else {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                        }
                        Text(cat.name)
                    }
                }
                // MARK: Delete Gesture: 下滑刪除分類 (Swipe to delete category)
                .onDelete { indices in
                    for i in indices {
                        let cat = vm.categories[i]
                        categoryToDelete = cat
                        showDeleteCatConfirm = true
                    }
                }
            }
        } header: {
            HStack {
                Text("分類 Categories")
                Spacer()
                // MARK: Add Button: 新增分類 (Add category button)
                Button {
                    showAddCategory = true
                } label: {
                    Image(systemName: "plus")
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Invitations Section (Manage)
    /// 管理帳戶和邀請
    /// Manage accounts and invitations
    private var invitationsSection: some View {
        Section("管理 Manage") {
            // MARK: Account List: 導航到帳戶管理 (Navigate to account management)
            NavigationLink {
                AccountListView()
                    .environment(accountVM)
                // txVM and profileVM come from the NavigationStack's environment
            } label: {
                Label("帳戶管理 Accounts", systemImage: "creditcard.fill")
            }

            // MARK: Invitations: 導航到邀請管理 (Navigate to invitations management)
            NavigationLink {
                InvitationsView()
                    .environment(accountVM)
            } label: {
                HStack {
                    Label("邀請管理 Invitations", systemImage: "envelope.fill")
                    Spacer()
                    // Hint text — actual pending count is shown in the Invitations tab badge
                    // 提示文字 — 實際待處理計數顯示在邀請標籤徽章中 (Hint text — actual count shown in badge)
                }
            }
        }
    }

    // MARK: - Sign Out
    /// 登出帳戶
    /// Sign out from account
    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                Task { await authVM.logout() }
            } label: {
                Label("登出 Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Default Account Picker Sheet
/// 選擇預設帳戶的 Sheet 表單
/// Sheet form for selecting default accounts
struct DefaultAccountPickerSheet: View {
    // MARK: - Environment: Injected view models
    @Environment(ProfileViewModel.self)  private var vm
    @Environment(AccountViewModel.self)  private var accountVM
    @Environment(\.dismiss)             private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let defaultIds = vm.profile?.defaultSharedAccounts ?? []
                ForEach(accountVM.accounts) { acc in
                    HStack {
                        Text(acc.name)
                        Spacer()
                        // MARK: Selection Indicator: 已選帳戶顯示勾選 (Selected accounts show checkmark)
                        if defaultIds.contains(acc.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var ids = defaultIds
                        if ids.contains(acc.id) {
                            ids.removeAll { $0 == acc.id }
                        } else {
                            ids.append(acc.id)
                        }
                        Task { await vm.updateDefaultAccounts(ids) }
                    }
                }
            }
            .navigationTitle("選擇預設帳戶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: Done Button: 完成選擇 (Done selecting)
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
