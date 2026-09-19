//
//  FamilyView.swift
//  family_account
//
//  家庭成員管理：成員列表 + 邀請家人。
//  之後對應後端 GET /families/current/members 與 POST /families/invitations。
//

import SwiftUI

struct FamilyView: View {
    @Environment(\.dismiss) private var dismiss
    var store: AppStore

    @State private var inviteeName = ""

    private var pendingInvitations: [FamilyInvitation] {
        store.invitations.filter { $0.status == .pending }
    }

    private var resolvedInvitations: [FamilyInvitation] {
        store.invitations.filter { $0.status != .pending }
    }

    var body: some View {
        NavigationStack {
            List {
                membersSection
                inviteSection
                if !pendingInvitations.isEmpty {
                    pendingSection
                }
                if !resolvedInvitations.isEmpty {
                    historySection
                }
            }
            .navigationTitle("家庭成員")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var membersSection: some View {
        Section("成員") {
            ForEach(store.members) { member in
                HStack(spacing: 12) {
                    MemberBadge(member: member)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.headline)
                        Text(member.id == store.currentMemberID ? "本機使用者" : "家庭成員")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if member.id == store.currentMemberID {
                        Text("我")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.teal.opacity(0.15))
                            .foregroundStyle(.teal)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var inviteSection: some View {
        Section {
            HStack(spacing: 10) {
                TextField("輸入名字或 email 邀請家人", text: $inviteeName)
                    .textInputAutocapitalization(.never)
                    .onSubmit(sendInvite)
                Button(action: sendInvite) {
                    Label("邀請", systemImage: "paperplane.fill")
                        .labelStyle(.titleOnly)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inviteeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("邀請家人")
        } footer: {
            Text("Prototype 階段邀請只存在本機；接上後端後會呼叫 POST /families/invitations，由對方在自己的裝置上接受。")
        }
    }

    private var pendingSection: some View {
        Section("等待回覆") {
            ForEach(pendingInvitations) { invitation in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "envelope.badge.fill")
                            .foregroundStyle(.teal)
                        Text(invitation.inviteeName)
                            .font(.headline)
                        Spacer()
                        Text(invitation.status.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("模擬對方接受") {
                            store.simulateAcceptInvitation(invitation.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("模擬婉拒") {
                            store.simulateDeclineInvitation(invitation.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button(role: .destructive) {
                            store.cancelInvitation(invitation.id)
                        } label: {
                            Text("取消邀請")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var historySection: some View {
        Section("邀請紀錄") {
            ForEach(resolvedInvitations) { invitation in
                HStack {
                    Image(systemName: invitation.status == .accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(invitation.status == .accepted ? .green : .secondary)
                    Text(invitation.inviteeName)
                    Spacer()
                    Text(invitation.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    store.cancelInvitation(resolvedInvitations[index].id)
                }
            }
        }
    }

    private func sendInvite() {
        store.invite(name: inviteeName)
        inviteeName = ""
    }
}

/// 成員色塊徽章（列表用，比交易列上的大一號）。
struct MemberBadge: View {
    let member: Member

    var body: some View {
        Text(member.initial)
            .font(.headline.bold())
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(member.color.color)
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

#Preview {
    FamilyView(store: AppStore())
}
