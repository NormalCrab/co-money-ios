import Foundation

// 帳本、成員、邀請、匯率（REQUIREMENTS N2 到 N5）。
// 和 Settings.swift 一樣：這些寫入都需要連線，不進待上傳佇列。

public enum MemberRole: String, Codable, Sendable, CaseIterable {
    case owner = "OWNER"
    case admin = "ADMIN"
    case member = "MEMBER"

    public var label: String {
        switch self {
        case .owner: "擁有者"
        case .admin: "管理員"
        case .member: "成員"
        }
    }
}

/// 帳本成員。`isActive == false` 是被管理員停用（人還在名單上），退出的人不會出現。
public struct Membership: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var user: User
    public var role: MemberRole
    public var isActive: Bool
    public var joinedAt: Date?
}

public enum InvitationStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
}

public struct Invitation: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var ledger: LedgerLite
    public var inviter: User
    public var invitee: User
    public var status: InvitationStatus
    public var createdAt: Date?
}

/// 帳本設定的匯率：1 單位外幣 = `rate` 單位帳本幣別（v2 §2.4）。
public struct ExchangeRate: Codable, Hashable, Sendable, Identifiable {
    public var currency: String
    public var rate: Money
    public var updatedBy: User?
    public var updatedAt: Date?

    public var id: String { currency }
}

/// 新增 / 修改帳本。新增只能建家庭帳本（每人最多一個）；帳本裡有交易之後不能改幣別。
public struct LedgerWrite: Encodable, Sendable {
    public var name: String
    public var description: String
    /// 修改時沒有要改幣別就不要送（有交易的帳本送了不同的幣別會被拒絕）。
    public var baseCurrency: String?
    public var timezone: String

    public init(name: String, description: String = "", baseCurrency: String? = nil, timezone: String) {
        self.name = name
        self.description = description
        self.baseCurrency = baseCurrency
        self.timezone = timezone
    }
}

private struct MemberUpdate: Encodable {
    var role: MemberRole?
    var isActive: Bool?
}

private struct ExchangeRatesBody: Encodable {
    struct Entry: Encodable {
        var currency: String
        var rate: Money
    }

    var rates: [Entry]
}

extension APIClient {
    // MARK: 帳本（N2）

    public func createLedger(_ ledger: LedgerWrite) async throws -> Ledger {
        try decode(try await send("POST", "api/v2/ledgers/", json: ledger))
    }

    public func updateLedger(_ id: UUID, with ledger: LedgerWrite) async throws -> Ledger {
        try decode(try await send("PATCH", "api/v2/ledgers/\(id.apiString)/", json: ledger))
    }

    /// 只有擁有者可以刪；家庭帳本裡的交易會一起刪除，私人帳本不能刪。
    public func deleteLedger(_ id: UUID) async throws {
        _ = try await send("DELETE", "api/v2/ledgers/\(id.apiString)/")
    }

    // MARK: 成員（N3）

    public func members(ledger: UUID) async throws -> [Membership] {
        try await get("api/v2/ledgers/\(ledger.apiString)/members/")
    }

    /// 改角色（只有擁有者）或停用 / 啟用（擁有者可以對任何人，管理員只能對一般成員）。
    public func updateMember(ledger: UUID, membership: UUID, role: MemberRole? = nil,
                             isActive: Bool? = nil) async throws -> Membership {
        let path = "api/v2/ledgers/\(ledger.apiString)/members/\(membership.apiString)/"
        return try decode(try await send("PATCH", path, json: MemberUpdate(role: role, isActive: isActive)))
    }

    /// 退出帳本。擁有者要先轉移擁有權；私人帳本不能退出。
    public func leaveLedger(_ id: UUID) async throws {
        _ = try await send("POST", "api/v2/ledgers/\(id.apiString)/leave/")
    }

    public func transferOwnership(ledger: UUID, to userId: Int) async throws -> [Membership] {
        try decode(try await send("POST", "api/v2/ledgers/\(ledger.apiString)/transfer-ownership/",
                                  json: ["user_id": userId]))
    }

    // MARK: 邀請（N4）

    /// 寄給自己、還沒處理的邀請。
    public func myInvitations() async throws -> [Invitation] {
        try await get("api/v2/invitations/mine/")
    }

    /// 這個帳本發出、還沒處理的邀請。
    public func sentInvitations(ledger: UUID) async throws -> [Invitation] {
        let all: [Invitation] = try await get("api/v2/invitations/")
        return all.filter { $0.ledger.id == ledger && $0.status == .pending }
    }

    /// 用使用者名稱或 email 邀請，對方會成為一般成員。
    public func invite(_ invitee: String, to ledger: UUID) async throws -> Invitation {
        try decode(try await send("POST", "api/v2/invitations/",
                                  json: ["ledger": ledger.apiString, "invitee": invitee]))
    }

    public func acceptInvitation(_ id: UUID) async throws {
        _ = try await send("POST", "api/v2/invitations/\(id.apiString)/accept/")
    }

    public func declineInvitation(_ id: UUID) async throws {
        _ = try await send("POST", "api/v2/invitations/\(id.apiString)/decline/")
    }

    /// 收回自己發出的邀請。
    public func cancelInvitation(_ id: UUID) async throws {
        _ = try await send("DELETE", "api/v2/invitations/\(id.apiString)/")
    }

    // MARK: 匯率（N5）

    public func exchangeRates(ledger: UUID) async throws -> [ExchangeRate] {
        try await get("api/v2/ledgers/\(ledger.apiString)/exchange-rates/")
    }

    /// 整批取代：送進去的清單就是之後的完整設定，沒列到的幣別會被刪除（所有成員都可以改）。
    public func setExchangeRates(ledger: UUID, _ rates: [(currency: String, rate: Money)]) async throws -> [ExchangeRate] {
        let body = ExchangeRatesBody(rates: rates.map { .init(currency: $0.currency, rate: $0.rate) })
        return try decode(try await send("PUT", "api/v2/ledgers/\(ledger.apiString)/exchange-rates/", json: body))
    }
}
