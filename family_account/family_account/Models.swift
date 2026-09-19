//
//  Models.swift
//  family_account
//
//  資料模型。raw value 全部對齊 BACKEND_API_SPEC.md 的 API 值，
//  之後接 Django 後端時 Codable 可以直接沿用，不需要再轉換。
//

import SwiftUI

// MARK: - Member / Family

/// 家庭成員。之後對應後端 GET /families/current/members 的 member 物件。
struct Member: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String        // 顯示名稱，例如 "Ting"
    var initial: String     // 徽章字，例如 "婷"
    var color: MemberColor

    init(id: UUID = UUID(), name: String, initial: String, color: MemberColor) {
        self.id = id
        self.name = name
        self.initial = initial
        self.color = color
    }
}

/// 成員代表色。存字串方便 Codable 與後端傳輸。
enum MemberColor: String, Codable, CaseIterable {
    case orange, green, blue, purple, pink, teal, indigo, red

    var color: Color {
        switch self {
        case .orange: .orange
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .teal: .teal
        case .indigo: .indigo
        case .red: .red
        }
    }
}

/// 邀請狀態，對應 spec 的 invitation status。
enum InvitationStatus: String, Codable {
    case pending
    case accepted
    case declined

    var label: String {
        switch self {
        case .pending: "等待回覆"
        case .accepted: "已加入"
        case .declined: "已婉拒"
        }
    }
}

/// 家庭邀請。之後對應 POST /families/invitations。
struct FamilyInvitation: Identifiable, Codable {
    let id: UUID
    var inviteeName: String
    var status: InvitationStatus
    let createdAt: Date

    init(id: UUID = UUID(), inviteeName: String, status: InvitationStatus = .pending, createdAt: Date = .now) {
        self.id = id
        self.inviteeName = inviteeName
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - Account

/// 帳本種類：一個人只有兩種 — 家庭共同帳與個人私房帳。
enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case shared
    case privateMoney = "private"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shared: "共同"
        case .privateMoney: "私房"
        }
    }
}

/// 首頁帳本切換範圍。
enum AccountScope: String, CaseIterable, Identifiable {
    case shared
    case privateMoney
    case overview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shared: "共同帳戶"
        case .privateMoney: "私房錢 🔒"
        case .overview: "Σ 總覽"
        }
    }
}

// MARK: - Category

/// 支出分類。raw value 對齊 spec 的 API 值（food/clothing/...）。
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food, clothing, housing, transport, education, entertainment, medical, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: "食"
        case .clothing: "衣"
        case .housing: "住"
        case .transport: "行"
        case .education: "育"
        case .entertainment: "樂"
        case .medical: "醫"
        case .other: "其他"
        }
    }

    var icon: String {
        switch self {
        case .food: "fork.knife"
        case .clothing: "tshirt.fill"
        case .housing: "house.fill"
        case .transport: "car.fill"
        case .education: "book.fill"
        case .entertainment: "sparkles"
        case .medical: "cross.case.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .food: .orange
        case .clothing: .pink
        case .housing: .indigo
        case .transport: .cyan
        case .education: .blue
        case .entertainment: .purple
        case .medical: .red
        case .other: .gray
        }
    }
}

// MARK: - Repeat Rule（結構化，取代原本的自由文字）

enum RepeatFrequency: String, Codable, CaseIterable, Identifiable {
    case none
    case weekly
    case monthly
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "不重複"
        case .weekly: "每週"
        case .monthly: "每月固定日"
        case .custom: "自訂"
        }
    }
}

enum CustomRepeatUnit: String, Codable, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "週"
        case .month: "個月"
        }
    }
}

/// 結構化的重複設定，對應 spec 的 recurring rule detail：
/// weekly → { weekday }、monthly → { dayOfMonth }、custom → { interval, unit }。
struct RepeatSetting: Codable, Equatable {
    var frequency: RepeatFrequency = .none
    /// 1 = 週日 … 7 = 週六（跟 Calendar.weekday 一致）
    var weekday: Int = 2
    var dayOfMonth: Int = 5
    var interval: Int = 2
    var unit: CustomRepeatUnit = .week

    static let none = RepeatSetting()

    static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    var label: String {
        switch frequency {
        case .none:
            return ""
        case .weekly:
            let name = Self.weekdayNames[max(0, min(weekday - 1, 6))]
            return "每週\(name)"
        case .monthly:
            return "每月 \(dayOfMonth) 日"
        case .custom:
            return "每 \(interval) \(unit.label)"
        }
    }
}

// MARK: - Transaction

/// 交易來源。isAI 由 source 推導，不再是獨立欄位（對齊 review 建議）。
enum TransactionSource: String, Codable {
    case manual
    case voice
    case receipt
}

struct TransactionItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var amount: Int
    var date: Date
    var category: ExpenseCategory
    var account: AccountKind
    /// 記錄者一律是「當下登入的成員」，UI 不提供修改（對齊 spec 的 recordedByUserId）。
    var recorderID: UUID
    var tags: [String]
    var repeatSetting: RepeatSetting
    var source: TransactionSource

    var isAI: Bool { source != .manual }

    var repeatLabel: String {
        repeatSetting.frequency == .none ? "" : "🔁 \(repeatSetting.label)"
    }

    init(
        id: UUID = UUID(),
        title: String,
        amount: Int,
        date: Date,
        category: ExpenseCategory,
        account: AccountKind,
        recorderID: UUID,
        tags: [String] = [],
        repeatSetting: RepeatSetting = .none,
        source: TransactionSource = .manual
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.category = category
        self.account = account
        self.recorderID = recorderID
        self.tags = tags
        self.repeatSetting = repeatSetting
        self.source = source
    }
}

// MARK: - Fixed Expense（週期性支出的待確認項目）

struct FixedExpense: Identifiable, Codable {
    let id: UUID
    let title: String
    let amount: Int
    let dueText: String
    let category: ExpenseCategory
    let tag: String
    /// 確認入帳時要帶進交易的重複設定。
    let repeatSetting: RepeatSetting

    init(
        id: UUID = UUID(),
        title: String,
        amount: Int,
        dueText: String,
        category: ExpenseCategory,
        tag: String,
        repeatSetting: RepeatSetting = .none
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.dueText = dueText
        self.category = category
        self.tag = tag
        self.repeatSetting = repeatSetting
    }
}

// MARK: - Project

enum ProjectStatus: String, Codable {
    case active
    case closed

    var label: String {
        switch self {
        case .active: "進行中"
        case .closed: "已結案"
        }
    }
}

/// 專案定義：只存 metadata；spent / 筆數 / 每月長條全部由交易即時計算。
struct ProjectDefinition: Identifiable, Codable {
    let id: UUID
    var title: String
    var tag: String
    var budget: Int
    var status: ProjectStatus
    var isFixed: Bool

    init(id: UUID = UUID(), title: String, tag: String, budget: Int, status: ProjectStatus = .active, isFixed: Bool = false) {
        self.id = id
        self.title = title
        self.tag = tag
        self.budget = budget
        self.status = status
        self.isFixed = isFixed
    }
}

// MARK: - Budget

struct BudgetPlan: Codable {
    var total: Int
    var categoryLimits: [ExpenseCategory: Int]
}

// MARK: - Sync

enum SyncChangeKind: String, Codable {
    case create
    case update
    case delete
    case skip

    var label: String {
        switch self {
        case .create: "新增"
        case .update: "修改"
        case .delete: "刪除"
        case .skip: "跳過"
        }
    }

    var color: Color {
        switch self {
        case .create: .green
        case .update: .blue
        case .delete: .red
        case .skip: .gray
        }
    }
}

/// 本機待同步變更（之後對應 POST /sync/push 的 mutation，id 即 clientMutationId）。
struct SyncChange: Identifiable, Codable {
    let id: UUID
    let kind: SyncChangeKind
    let title: String
    let amount: Int
    let source: String
    let createdAt: Date

    init(id: UUID = UUID(), kind: SyncChangeKind, title: String, amount: Int, source: String, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.title = title
        self.amount = amount
        self.source = source
        self.createdAt = createdAt
    }
}

// MARK: - Shared Helpers

func currency(_ amount: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "TWD"
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: amount)) ?? "NT$\(amount)"
}
