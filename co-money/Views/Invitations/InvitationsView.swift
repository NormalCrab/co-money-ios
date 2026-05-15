// InvitationsView.swift
// co-money

import SwiftUI

/// InvitationsView: 邀請管理檢視
/// Displays and manages invitations in two sections:
/// 1. Received invitations: Invitations sent to the current user
///    - Accept/Decline actions
///    - Shows inviter name and target account
/// 2. Sent invitations: Invitations sent by the current user
///    - Shows status (pending, accepted, declined)
///    - Shows invitee and target account
struct InvitationsView: View {
    // MARK: - Environment: Injected view models
    @Environment(AccountViewModel.self) private var accountVM

    // MARK: - State: Invitations and loading state
    // MARK: 邀請列表和載入狀態 (Invitations list and loading state)
    @State private var received:     [Invitation] = []
    @State private var sent:         [Invitation] = []
    @State private var isLoading     = false
    @State private var errorMessage: String?

    // MARK: - Sheet State: For sending new invitations
    // MARK: 發送邀請表單狀態 (Send invitation form state)
    @State private var showInvite      = false
    @State private var isInviting      = false

    private let service = AccountService.shared

    var body: some View {
        List {
            // ────── RECEIVED INVITATIONS ──────────────────────────────────
            // MARK: Received Section: 收到的邀請 (Received invitations)
            Section {
                if isLoading && received.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if received.isEmpty {
                    // MARK: Empty State: 沒有待處理邀請 (No pending invitations)
                    Text("目前沒有待處理邀請")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    // MARK: Invitation List: 顯示收到的邀請 (Show received invitations)
                    ForEach(received) { inv in
                        ReceivedInvitationRow(
                            invitation: inv,
                            accounts:   accountVM.accounts
                        ) {
                            Task { await accept(inv) }
                        } onDecline: {
                            Task { await decline(inv) }
                        }
                    }
                }
            } header: {
                Text("收到的邀請 Received")
            }

            // ────── SENT INVITATIONS ───────────────────────────────────────
            // MARK: Sent Section: 已發送的邀請 (Sent invitations)
            Section {
                if sent.isEmpty && !isLoading {
                    // MARK: Empty State: 尚未發送任何邀請 (No invitations sent)
                    Text("尚未發送任何邀請")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    // MARK: Invitation List: 顯示已發送的邀請 (Show sent invitations)
                    ForEach(sent) { inv in
                        SentInvitationRow(invitation: inv, accounts: accountVM.accounts)
                    }
                }
            } header: {
                HStack {
                    Text("已發送邀請 Sent")
                    Spacer()
                    // MARK: Add Button: 發送新邀請 (Send new invitation)
                    Button {
                        showInvite = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle("邀請 Invitations")
        .navigationBarTitleDisplayMode(.inline)
        // MARK: Pull-to-Refresh: 下拉重新載入邀請 (Pull to refresh invitations)
        .refreshable { await load() }
        // MARK: Initial Load: 檢視載入時獲取邀請 (Load invitations when view appears)
        .task { await load() }
        // MARK: Send Invite Sheet: 發送邀請表單 (Sheet for sending invitations)
        .sheet(isPresented: $showInvite) {
            SendInvitationSheet(
                accounts: accountVM.accounts,
                preselectedAccountId: nil,
                isPresented: $showInvite
            ) { accountId, username in
                Task { await sendInvite(accountId: accountId, username: username) }
            }
        }
        // MARK: Error Alert: 顯示錯誤訊息 (Show error messages)
        .alert("錯誤", isPresented: .constant(errorMessage != nil)) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Load

    /// Load both received and sent invitations
    /// 同時載入收到的和已發送的邀請 (Load both received and sent invitations)
    private func load() async {
        isLoading    = true
        errorMessage = nil
        // MARK: Concurrent Load: 並行載入兩個 API 請求 (Load both APIs concurrently)
        async let r = service.getMyInvitations()
        async let s = service.getSentInvitations()
        do {
            (received, sent) = try await (r, s)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Actions

    /// Accept an invitation to join a shared account
    /// 接受邀請加入共享帳戶 (Accept invitation to join account)
    private func accept(_ inv: Invitation) async {
        do {
            try await service.acceptInvitation(id: inv.id)
            // MARK: Update State: 從列表移除已接受的邀請 (Remove from received list)
            received.removeAll { $0.id == inv.id }
            // MARK: Reload Accounts: 重新載入帳戶列表 (Reload account list)
            await accountVM.loadAccounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Decline an invitation
    /// 拒絕邀請 (Decline invitation)
    private func decline(_ inv: Invitation) async {
        do {
            try await service.declineInvitation(id: inv.id)
            // MARK: Update State: 從列表移除已拒絕的邀請 (Remove from received list)
            received.removeAll { $0.id == inv.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Send a new invitation to a user
    /// 向使用者發送新邀請 (Send invitation to user)
    private func sendInvite(accountId: String, username: String) async {
        isInviting   = true
        errorMessage = nil
        do {
            // MARK: API Call: 後端創建邀請 (Backend creates invitation)
            let inv = try await service.inviteMember(accountId: accountId, inviteeUsername: username)
            // MARK: Update State: 新邀請插入到列表開頭 (Insert new invitation at beginning)
            sent.insert(inv, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
        isInviting = false
    }
}

// MARK: - Received Invitation Row
/// 收到的邀請列行項目，顯示帳戶、邀請者、日期和接受/拒絕按鈕
/// Row for received invitation showing account, inviter, date, and accept/decline buttons
struct ReceivedInvitationRow: View {
    let invitation: Invitation
    let accounts:   [SharedAccount]   // for account name lookup
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
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    // MARK: Account Name: 目標帳戶名稱 (Target account name)
                    Text(accountName)
                        .font(.subheadline.bold())
                    if let inviter = invitation.inviter {
                        // MARK: Inviter: 邀請者用戶名 (Inviter username)
                        Label(inviter.username, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // MARK: Date: 邀請日期 (Invitation date)
                    Text(invitation.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                // MARK: Status Badge: 顯示邀請狀態 (Show invitation status)
                statusBadge
            }

            HStack(spacing: 12) {
                // MARK: Accept Button: 接受邀請 (Accept invitation)
                Button {
                    onAccept()
                } label: {
                    Text("接受 Accept")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // MARK: Decline Button: 拒絕邀請 (Decline invitation)
                Button {
                    onDecline()
                } label: {
                    Text("拒絕 Decline")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    /// Status Badge: 顯示邀請狀態標籤 (Show status badge)
    @ViewBuilder
    private var statusBadge: some View {
        if let status = invitation.status {
            Text(status.displayName)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.15))
                .foregroundStyle(status.color)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Sent Invitation Row
/// 已發送邀請列行項目，顯示帳戶、被邀請者、日期和狀態
/// Row for sent invitation showing account, invitee, date, and status
struct SentInvitationRow: View {
    let invitation: Invitation
    let accounts:   [SharedAccount]

    /// Resolve account UUID to display name
    /// 解析帳戶 UUID 為顯示名稱 (Resolve account ID to name)
    private var accountName: String {
        accounts.first(where: { $0.id == invitation.account })?.name
            ?? "帳戶 \(invitation.account.prefix(8))…"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                // MARK: Account Name: 目標帳戶名稱 (Target account name)
                Text(accountName)
                    .font(.subheadline.bold())
                if let display = invitation.inviteeDisplay {
                    // MARK: Invitee: 被邀請者用戶名 (Invitee username)
                    Label(display, systemImage: "person.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // MARK: Date: 邀請日期 (Invitation date)
                Text(invitation.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            // MARK: Status Badge: 顯示邀請狀態 (Show invitation status)
            if let status = invitation.status {
                Text(status.displayName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.15))
                    .foregroundStyle(status.color)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Send Invitation Sheet
/// 發送邀請的表單 Sheet，包含帳戶選擇器和用戶名輸入
/// Sheet form for sending invitations with account picker and username input
struct SendInvitationSheet: View {
    let accounts:             [SharedAccount]
    let preselectedAccountId: String?          // optional: pre-select a specific account
    @Binding var isPresented: Bool
    let onSend: (_ accountId: String, _ username: String) -> Void

    // MARK: - Form State: 表單狀態 (Form state)
    @State private var selectedAccountId = ""
    @State private var username          = ""
    @State private var isSending         = false

    /// Validation: 檢查是否可以發送 (Check if can send)
    private var canSend: Bool {
        !selectedAccountId.isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Account Picker: 選擇目標帳戶 (Select target account)
                Section("選擇帳戶") {
                    if accounts.isEmpty {
                        Text("尚無帳戶，請先建立共享帳戶")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("帳戶", selection: $selectedAccountId) {
                            Text("選擇...").tag("")
                            ForEach(accounts) { acc in
                                Text(acc.name).tag(acc.id)
                            }
                        }
                    }
                }

                // MARK: Username Input: 輸入被邀請者用戶名 (Input invitee username)
                Section("被邀請人") {
                    TextField("用戶名稱 Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("發送邀請")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: Cancel Button: 關閉表單 (Close form)
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                // MARK: Send Button: 發送邀請 (Send invitation)
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("發送") {
                            isSending = true
                            onSend(selectedAccountId, username.trimmingCharacters(in: .whitespaces))
                            isPresented = false
                        }
                        // MARK: Disabled State: 表單驗證未通過時禁用 (Disable when validation fails)
                        .disabled(!canSend)
                    }
                }
            }
            // MARK: On Appear: 預設選擇帳戶 (Pre-select account on appear)
            .onAppear {
                selectedAccountId = preselectedAccountId ?? accounts.first?.id ?? ""
            }
        }
    }
}

// MARK: - InvitationStatus Helpers
/// 邀請狀態顯示名稱和顏色的擴展 (Extension for status display name and color)
extension InvitationStatus {
    /// Display name in Chinese
    /// 顯示名稱（中文） (Display name in Chinese)
    var displayName: String {
        switch self {
        case .pending:  return "待處理"
        case .accepted: return "已接受"
        case .declined: return "已拒絕"
        }
    }

    /// Color for status badge
    /// 狀態徽章的顏色 (Color for status badge)
    var color: Color {
        switch self {
        case .pending:  return .orange
        case .accepted: return .green
        case .declined: return .red
        }
    }
}
