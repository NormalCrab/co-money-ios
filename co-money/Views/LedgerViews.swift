import MMCore
import SwiftUI

/// 執行一個需要連線的寫入，失敗時回傳給使用者看的訊息（後端的訊息已經是中文）。
@MainActor
func runRequest(_ work: () async throws -> Void) async -> String? {
    do {
        try await work()
        return nil
    } catch let error as APIError {
        return error.message
    } catch {
        return error.localizedDescription
    }
}

extension Ledger {
    var role: MemberRole? { myRole.flatMap(MemberRole.init(rawValue:)) }
    var isPersonal: Bool { kind == .personal }
    /// 擁有者和管理員可以改帳本資料。
    var canEdit: Bool { role == .owner || role == .admin }
}

// MARK: - 帳本清單（N2）

/// 我的所有帳本：新增、進入設定（成員、匯率、退出、刪除）。
struct LedgersView: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            List {
                ForEach(model.ledgers) { ledger in
                    NavigationLink {
                        LedgerDetailView(ledgerId: ledger.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(ledger.name)
                                if ledger.id == model.selectedLedger?.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                                }
                            }
                            Text(summary(ledger)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("帳本")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .refreshable { await model.refreshAll() }
        .sheet(isPresented: $creating) { LedgerEditor() }
    }

    private func summary(_ ledger: Ledger) -> String {
        var parts = [ledger.isPersonal ? "私人" : "家庭", ledger.currency]
        if let count = ledger.memberCount, !ledger.isPersonal { parts.append("\(count) 位成員") }
        if let role = ledger.role { parts.append(role.label) }
        return parts.joined(separator: "・")
    }
}

/// 新增 / 修改帳本。新增只能建家庭帳本（每人最多一個）；帳本裡有交易之後不能改幣別。
struct LedgerEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var editing: Ledger?

    @State private var name = ""
    @State private var description = ""
    @State private var currency = "TWD"
    @State private var timezone = TimeZone.current.identifier
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱", text: $name)
                    TextField("說明（可以不填）", text: $description)
                }
                Section {
                    Picker("幣別", selection: $currency) {
                        ForEach(Currencies.options(base: currency), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("時區", selection: $timezone) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("月份的界線和「今天」依帳本的時區計算。帳本裡有交易之後就不能改幣別。")
                }
                FormStatus(error: error, needsConnection: model.isOffline)
            }
            .navigationTitle(editing == nil ? "新增家庭帳本" : "帳本資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { Task { await save() } }.bold().disabled(!canSave)
                }
            }
            .onAppear {
                guard let editing else { return }
                name = editing.name
                description = editing.description ?? ""
                currency = editing.currency
                timezone = editing.timezone ?? timezone
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving && !model.isOffline
    }

    private func save() async {
        isSaving = true
        error = await runRequest {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if let editing {
                // 幣別沒改就不送：有交易的帳本送了幣別（即使相同）也不需要走那條檢查。
                let changed = currency != editing.currency
                _ = try await model.api.updateLedger(editing.id, with: LedgerWrite(
                    name: trimmed, description: description, baseCurrency: changed ? currency : nil,
                    timezone: timezone))
            } else {
                let created = try await model.api.createLedger(LedgerWrite(
                    name: trimmed, description: description, baseCurrency: currency, timezone: timezone))
                await model.selectLedger(created.id)
            }
        }
        isSaving = false
        guard error == nil else { return }
        await model.refreshAll()
        dismiss()
    }
}

// MARK: - 帳本設定（N2、N3、N5）

struct LedgerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ledgerId: UUID

    @State private var editing = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var error: String?

    private var ledger: Ledger? { model.ledgers.first { $0.id == ledgerId } }

    var body: some View {
        if let ledger {
            content(ledger)
        } else {
            // 剛退出或刪除：資料已經不在清單裡了。
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ ledger: Ledger) -> some View {
        Form {
            Section {
                LabeledContent("名稱", value: ledger.name)
                if let description = ledger.description, !description.isEmpty {
                    LabeledContent("說明", value: description)
                }
                LabeledContent("幣別", value: ledger.currency)
                LabeledContent("時區", value: ledger.timezone ?? "—")
                if let role = ledger.role { LabeledContent("我的角色", value: role.label) }
                if ledger.canEdit { Button("修改帳本資料") { editing = true } }
            }

            Section {
                if !ledger.isPersonal {
                    NavigationLink("成員") { MembersView(ledger: ledger) }
                }
                NavigationLink("匯率") { ExchangeRatesView(ledger: ledger) }
                if ledger.id != model.selectedLedger?.id {
                    Button("設為目前帳本") { Task { await model.selectLedger(ledger.id) } }
                }
            }

            if !ledger.isPersonal {
                Section {
                    Button("退出帳本", role: .destructive) { confirmLeave = true }
                    if ledger.role == .owner {
                        Button("刪除帳本", role: .destructive) { confirmDelete = true }
                    }
                } footer: {
                    Text("擁有者要先把擁有權轉移給其他成員才能退出。退出後你付過的交易會留在帳本裡，但你看不到了。")
                }
            }
            FormStatus(error: error, needsConnection: model.isOffline)
        }
        .navigationTitle(ledger.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { LedgerEditor(editing: ledger) }
        .confirmationDialog("退出「\(ledger.name)」？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("退出帳本", role: .destructive) { Task { await leave(ledger) } }
        }
        .confirmationDialog("刪除「\(ledger.name)」？帳本裡所有交易都會一起刪除，無法復原。",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("刪除帳本和所有交易", role: .destructive) { Task { await delete(ledger) } }
        }
    }

    private func leave(_ ledger: Ledger) async {
        error = await runRequest { try await model.api.leaveLedger(ledger.id) }
        if error == nil { await model.refreshAll() }
    }

    private func delete(_ ledger: Ledger) async {
        error = await runRequest { try await model.api.deleteLedger(ledger.id) }
        if error == nil { await model.refreshAll() }
    }
}

// MARK: - 成員與邀請（N3、N4）

struct MembersView: View {
    @Environment(AppModel.self) private var model
    let ledger: Ledger

    @State private var members: [Membership] = []
    @State private var invitations: [Invitation] = []
    @State private var selected: Membership?
    @State private var inviting = false
    @State private var error: String?

    private var myRole: MemberRole? { ledger.role }

    var body: some View {
        List {
            Section("成員") {
                ForEach(members) { member in
                    Button { selected = member } label: {
                        HStack {
                            Text(member.user.username).foregroundStyle(.primary)
                            Spacer()
                            if !member.isActive { Text("已停用").font(.caption).foregroundStyle(Palette.warning) }
                            Text(member.role.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(actions(for: member).isEmpty)
                }
            }
            if !invitations.isEmpty {
                Section("已邀請，等對方回應") {
                    ForEach(invitations) { invitation in
                        Text(invitation.invitee.username)
                            .swipeActions {
                                Button("收回", role: .destructive) { Task { await cancel(invitation) } }
                            }
                    }
                }
            }
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Palette.warning) }
            }
        }
        .navigationTitle("成員")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { inviting = true } label: { Image(systemName: "person.badge.plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $inviting) {
            InviteSheet(ledger: ledger) { await load() }
        }
        .confirmationDialog(selected?.user.username ?? "", isPresented: Binding(
            get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
            if let member = selected {
                ForEach(actions(for: member), id: \.self) { action in
                    Button(action.title, role: action.isDestructive ? .destructive : nil) {
                        Task { await perform(action, on: member) }
                    }
                }
            }
        }
    }

    enum Action: Hashable {
        case makeAdmin, makeMember, deactivate, activate, transfer

        var title: String {
            switch self {
            case .makeAdmin: "設為管理員"
            case .makeMember: "設為一般成員"
            case .deactivate: "停用"
            case .activate: "重新啟用"
            case .transfer: "轉移擁有權給他"
            }
        }

        var isDestructive: Bool { self == .deactivate || self == .transfer }
    }

    /// 對這位成員可以做的事（規則見 v2 §3.1，後端還會再檢查一次）：
    /// 擁有者可以改角色、停用任何人、轉移擁有權；管理員只能停用或啟用一般成員。
    private func actions(for member: Membership) -> [Action] {
        guard member.role != .owner, member.user.id != model.userId else { return [] }
        var result: [Action] = []
        let toggle: Action = member.isActive ? .deactivate : .activate
        switch myRole {
        case .owner:
            result.append(member.role == .admin ? .makeMember : .makeAdmin)
            result.append(toggle)
            if member.isActive { result.append(.transfer) }
        case .admin:
            if member.role == .member { result.append(toggle) }
        default:
            break
        }
        return result
    }

    private func perform(_ action: Action, on member: Membership) async {
        error = await runRequest {
            switch action {
            case .makeAdmin: _ = try await model.api.updateMember(ledger: ledger.id, membership: member.id, role: .admin)
            case .makeMember: _ = try await model.api.updateMember(ledger: ledger.id, membership: member.id, role: .member)
            case .deactivate: _ = try await model.api.updateMember(ledger: ledger.id, membership: member.id, isActive: false)
            case .activate: _ = try await model.api.updateMember(ledger: ledger.id, membership: member.id, isActive: true)
            case .transfer: _ = try await model.api.transferOwnership(ledger: ledger.id, to: member.user.id)
            }
        }
        await load()
        if action == .transfer { await model.refreshAll() }  // 我的角色變了
    }

    private func cancel(_ invitation: Invitation) async {
        error = await runRequest { try await model.api.cancelInvitation(invitation.id) }
        await load()
    }

    private func load() async {
        if let list = try? await model.api.members(ledger: ledger.id) { members = list }
        if let list = try? await model.api.sentInvitations(ledger: ledger.id) { invitations = list }
    }
}

struct InviteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger
    var onSent: () async -> Void

    @State private var invitee = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("對方的使用者名稱或 email", text: $invitee)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("對方接受後會成為一般成員。每個人最多只能屬於一個家庭帳本。")
                }
                FormStatus(error: error, needsConnection: model.isOffline)
            }
            .navigationTitle("邀請成員")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送出邀請") { Task { await send() } }.bold()
                        .disabled(invitee.trimmingCharacters(in: .whitespaces).isEmpty || isSending || model.isOffline)
                }
            }
        }
    }

    private func send() async {
        isSending = true
        error = await runRequest {
            _ = try await model.api.invite(invitee.trimmingCharacters(in: .whitespaces), to: ledger.id)
        }
        isSending = false
        guard error == nil else { return }
        await onSent()
        dismiss()
    }
}

/// 寄給我的邀請：接受或拒絕。
struct InvitationsView: View {
    @Environment(AppModel.self) private var model
    @State private var invitations: [Invitation] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            ForEach(invitations) { invitation in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(invitation.inviter.username) 邀請你加入「\(invitation.ledger.name)」")
                    HStack {
                        Button("接受") { Task { await accept(invitation) } }.buttonStyle(.borderedProminent)
                        Button("拒絕", role: .destructive) { Task { await decline(invitation) } }
                            .buttonStyle(.bordered)
                    }
                    .disabled(model.isOffline)
                }
            }
            if loaded && invitations.isEmpty {
                Text("沒有待處理的邀請").foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Palette.warning)
            }
        }
        .navigationTitle("收到的邀請")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if let list = try? await model.api.myInvitations() { invitations = list }
        loaded = true
    }

    private func accept(_ invitation: Invitation) async {
        error = await runRequest { try await model.api.acceptInvitation(invitation.id) }
        await load()
        if error == nil { await model.refreshAll() }  // 多了一個帳本
    }

    private func decline(_ invitation: Invitation) async {
        error = await runRequest { try await model.api.declineInvitation(invitation.id) }
        await load()
    }
}

// MARK: - 匯率（N5）

/// 帳本的匯率：1 單位外幣 = 多少帳本幣別。所有成員都可以改；儲存是整批取代。
struct ExchangeRatesView: View {
    @Environment(AppModel.self) private var model
    let ledger: Ledger

    struct Row: Identifiable, Hashable {
        let id = UUID()
        var currency: String
        var text: String
    }

    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                ForEach($rows) { $row in
                    HStack {
                        Text("1 \(row.currency) =")
                        TextField("0", text: $row.text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text(ledger.currency).foregroundStyle(.secondary)
                    }
                }
                .onDelete { rows.remove(atOffsets: $0) }
                if loaded && rows.isEmpty {
                    Text("還沒有設定任何匯率").foregroundStyle(.secondary)
                }
                if !addable.isEmpty {
                    Menu("新增幣別") {
                        ForEach(addable, id: \.self) { code in
                            Button(code) { rows.append(Row(currency: code, text: "")) }
                        }
                    }
                }
            } footer: {
                Text("外幣交易依這裡的匯率換算成 \(ledger.currency)。已經記下的交易用的是當時的匯率，不會跟著改。")
            }
            if saved { Section { Text("已儲存").font(.footnote).foregroundStyle(.secondary) } }
            FormStatus(error: error, needsConnection: model.isOffline)
        }
        .navigationTitle("匯率")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") { Task { await save() } }.bold().disabled(!canSave)
            }
        }
        .task { await load() }
    }

    private var addable: [String] {
        Currencies.all.filter { code in code != ledger.currency && !rows.contains { $0.currency == code } }
    }

    private func parsed(_ row: Row) -> Money? {
        guard let money = Money(userInput: row.text), money.value > 0 else { return nil }
        return money
    }

    private var canSave: Bool {
        loaded && !isSaving && !model.isOffline && rows.allSatisfy { parsed($0) != nil }
    }

    private func load() async {
        if let list = try? await model.api.exchangeRates(ledger: ledger.id) {
            rows = list.map { Row(currency: $0.currency, text: $0.rate.apiString) }
        }
        loaded = true
    }

    private func save() async {
        isSaving = true
        saved = false
        error = await runRequest {
            let rates = rows.compactMap { row in parsed(row).map { (currency: row.currency, rate: $0) } }
            let result = try await model.api.setExchangeRates(ledger: ledger.id, rates)
            rows = result.map { Row(currency: $0.currency, text: $0.rate.apiString) }
        }
        isSaving = false
        saved = error == nil
    }
}
