// AccountListView.swift
// co-money

import SwiftUI

/// AccountListView: 共享帳戶列表檢視
/// Displays list of shared accounts with summary (balance, income, expense).
/// Users can create new accounts, delete existing ones, and navigate to account details.
struct AccountListView: View {
    // MARK: - Environment: Injected view models
    @Environment(AccountViewModel.self)     private var vm
    @Environment(TransactionViewModel.self) private var txVM
    @Environment(ProfileViewModel.self)     private var profileVM

    // MARK: - Sheet State: For creating new accounts
    @State private var showCreate = false
    @State private var newName    = ""
    @State private var newDesc    = ""

    var body: some View {
        NavigationStack {
            Group {
                // MARK: Loading State: 初始載入時顯示進度 (Show progress during initial load)
                if vm.isLoading && vm.accounts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                // MARK: Empty State: 沒有帳戶時顯示提示 (Show hint when no accounts)
                } else if vm.accounts.isEmpty {
                    ContentUnavailableView(
                        "尚無帳戶",
                        systemImage: "person.2",
                        description: Text("點擊右上角 + 建立共享帳戶")
                    )
                // MARK: Account List: 帳戶卡片列表 (List of account cards)
                } else {
                    List {
                        ForEach(vm.accounts) { account in
                            // MARK: Navigation: 點擊帳戶進入詳情檢視 (Tap account to enter detail view)
                            NavigationLink {
                                AccountDetailView(
                                    cardTitle:  account.name,
                                    accountId:  account.id,
                                    account:    account
                                )
                                .environment(txVM)
                                .environment(vm)
                                .environment(profileVM)
                            } label: {
                                AccountCardRow(
                                    account: account,
                                    summary: txVM.summary(forAccountId: account.id)
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                        // MARK: Delete: 下滑刪除帳戶 (Swipe to delete account)
                        .onDelete { indices in
                            for i in indices {
                                Task { await vm.deleteAccount(id: vm.accounts[i].id) }
                            }
                        }
                    }
                    .listStyle(.plain)
                    // MARK: Pull-to-Refresh: 下拉重新載入帳戶列表 (Pull to refresh account list)
                    .refreshable { await vm.loadAccounts() }
                }
            }
            .navigationTitle("帳戶 Accounts")
            .toolbar {
                // MARK: Create Button: 建立新帳戶 (Create new account)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            // MARK: Create Sheet: 建立新帳戶的表單 (Sheet for creating new account)
            .sheet(isPresented: $showCreate) {
                CreateAccountSheet(isPresented: $showCreate)
                    .environment(vm)
            }
            // MARK: Error Alert: 顯示錯誤訊息 (Show error messages)
            .alert("錯誤", isPresented: .constant(vm.errorMessage != nil)) {
                Button("確定") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }
}

// MARK: - Account Card Row
/// 帳戶卡片列表行項目，顯示帳戶名稱、描述、結餘、收入和支出
/// Account card row showing account name, description, balance, income, and expense
struct AccountCardRow: View {
    let account: SharedAccount
    let summary: TransactionSummary?   // client-computed, passed in from AccountListView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Header: 帳戶名稱、描述、結餘 (Account name, description, balance)
            HStack(spacing: 12) {
                // MARK: Avatar: 帳戶名稱首字母圓形頭像 (Avatar with account's first letter)
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Text(String(account.name.prefix(1)).uppercased())
                        .font(.headline.bold())
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let desc = account.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // MARK: Balance Display: 右側顯示結餘 (Show balance on right)
                if let s = summary {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("結餘")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(s.balanceText)
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(s.balance >= 0 ? Color.accentColor : .orange)
                    }
                }
            }
            .padding(14)

            // MARK: Income/Expense Row: 顯示收入和支出 (Show income and expense)
            if let s = summary, s.income > 0 || s.expense > 0 {
                Divider().padding(.horizontal, 14)

                HStack {
                    // MARK: Income: 綠色向下箭頭，表示收入 (Green down arrow indicating income)
                    Label(s.incomeText, systemImage: "arrow.down.circle.fill")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green)
                    Spacer()
                    // MARK: Expense: 紅色向上箭頭，表示支出 (Red up arrow indicating expense)
                    Label(s.expenseText, systemImage: "arrow.up.circle.fill")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
    }
}

// MARK: - Create Account Sheet
/// 建立新帳戶的表單 Sheet
/// Modal form for creating a new shared account
struct CreateAccountSheet: View {
    @Binding var isPresented: Bool
    @Environment(AccountViewModel.self) private var vm

    // MARK: - Form State: 帳戶建立表單的狀態 (State for account creation form)
    @State private var name        = ""
    @State private var description = ""
    @State private var isCreating  = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Account Info Section: 輸入帳戶名稱和說明 (Input account name and description)
                Section("帳戶資訊") {
                    TextField("名稱 Name *", text: $name)
                    TextField("說明 Description（選填）", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("建立帳戶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: Cancel Button: 關閉表單 (Close form)
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                // MARK: Create Button: 提交表單建立帳戶 (Submit form to create account)
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("建立") {
                            isCreating = true
                            Task {
                                await vm.createAccount(
                                    name: name,
                                    description: description.isEmpty ? nil : description
                                )
                                isPresented = false
                            }
                        }
                        // MARK: Validation: 名稱不能為空 (Name cannot be empty)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
