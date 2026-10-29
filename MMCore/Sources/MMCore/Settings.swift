import Foundation

// 設定類的資料：tag 與預算、週期預算規則、重複交易規則（REQUIREMENTS N6、N7、N8）。
// 這些寫入都需要連線，不進待上傳佇列：改規則不是「記一筆帳」，離線排隊再送出的風險比好處大。

public enum Frequency: String, Codable, CaseIterable, Sendable, Identifiable {
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .weekly: "每週"
        case .monthly: "每月"
        case .yearly: "每年"
        }
    }
}

/// 週期 tag 的產生規則（v2 §2.6）：依 frequency 每一期產生一個 tag，各有預算。
public struct TagRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var ledger: LedgerLite
    public var name: String
    public var budgetAmount: Money?
    public var frequency: Frequency
    public var isActive: Bool
}

/// 重複交易規則（v2 §2.7）。金額二選一：本幣 `amount`，或外幣 `originalAmount` + `originalCurrency`。
public struct RecurringRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var ledger: LedgerLite
    public var payer: User
    public var description: String
    public var transactionType: TransactionType
    public var category: TransactionCategory
    public var notes: String?
    public var amount: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?
    public var tags: [UUID]
    public var frequency: Frequency
    /// 每週：ISO 星期 1（週一）到 7（週日）；每月、每年：幾號（1–31，短的月份用最後一天）。
    public var day: Int
    public var startDate: LocalDate
    public var endDate: LocalDate?
    public var nextRunDate: LocalDate
    public var isActive: Bool
}

/// 新增 / 修改 tag（一次性 tag；週期 tag 由 `TagRule` 產生）。
/// 預算金額清掉時要明確送 null，只是省略的話後端會保留舊的。
public struct TagWrite: Encodable, Sendable {
    /// 新增時要給；修改時不送（tag 不能換帳本）。
    public var ledgerId: UUID?
    public var name: String
    public var budgetAmount: Money?
    public var isArchived: Bool

    public init(ledgerId: UUID? = nil, name: String, budgetAmount: Money? = nil, isArchived: Bool = false) {
        self.ledgerId = ledgerId
        self.name = name
        self.budgetAmount = budgetAmount
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case ledgerId, name, budgetAmount, isArchived
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ledgerId, forKey: .ledgerId)
        try container.encode(name, forKey: .name)
        try container.encode(budgetAmount, forKey: .budgetAmount)
        try container.encode(isArchived, forKey: .isArchived)
    }
}

public struct TagRuleWrite: Encodable, Sendable {
    /// 新增時要給；修改時不送（規則不能換帳本）。
    public var ledgerId: UUID?
    public var name: String
    public var budgetAmount: Money?
    public var frequency: Frequency
    public var isActive: Bool

    public init(ledgerId: UUID? = nil, name: String, budgetAmount: Money? = nil,
                frequency: Frequency, isActive: Bool = true) {
        self.ledgerId = ledgerId
        self.name = name
        self.budgetAmount = budgetAmount
        self.frequency = frequency
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case ledgerId, name, budgetAmount, frequency, isActive
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ledgerId, forKey: .ledgerId)
        try container.encode(name, forKey: .name)
        try container.encode(budgetAmount, forKey: .budgetAmount)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(isActive, forKey: .isActive)
    }
}

/// 新增 / 修改重複交易規則。付款人固定是建立者（後端決定）。
/// 本幣和外幣只能填一種，所以沒用到的欄位要明確送 null（修改時才能從外幣改回本幣）。
public struct RecurringRuleWrite: Encodable, Sendable {
    /// 新增時要給；修改時不送（規則不能換帳本）。
    public var ledgerId: UUID?
    public var description: String
    public var transactionType: TransactionType
    public var category: TransactionCategory
    public var notes: String
    public var amount: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?
    public var tags: [UUID]
    public var frequency: Frequency
    public var day: Int
    public var startDate: LocalDate
    public var endDate: LocalDate?
    public var isActive: Bool

    public init(ledgerId: UUID? = nil, description: String, transactionType: TransactionType,
                category: TransactionCategory, notes: String = "", amount: Money? = nil,
                originalAmount: Money? = nil, originalCurrency: String? = nil, tags: [UUID] = [],
                frequency: Frequency, day: Int, startDate: LocalDate, endDate: LocalDate? = nil,
                isActive: Bool = true) {
        self.ledgerId = ledgerId
        self.description = description
        self.transactionType = transactionType
        self.category = category
        self.notes = notes
        self.amount = amount
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.tags = tags
        self.frequency = frequency
        self.day = day
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case ledgerId, description, transactionType, category, notes, amount, originalAmount
        case originalCurrency, tags, frequency, day, startDate, endDate, isActive
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ledgerId, forKey: .ledgerId)
        try container.encode(description, forKey: .description)
        try container.encode(transactionType, forKey: .transactionType)
        try container.encode(category, forKey: .category)
        try container.encode(notes, forKey: .notes)
        try container.encode(amount, forKey: .amount)
        try container.encode(originalAmount, forKey: .originalAmount)
        try container.encode(originalCurrency, forKey: .originalCurrency)
        try container.encode(tags, forKey: .tags)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(day, forKey: .day)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(isActive, forKey: .isActive)
    }
}

extension APIClient {
    // MARK: Tag 與預算（N6）

    /// 已封存的 tag（預算頁「顯示已封存」用）。
    public func archivedTags(ledger: UUID) async throws -> [Tag] {
        try await getAllPages("api/v2/tags/", query: ["ledger": ledger.apiString, "is_archived": "true"])
    }

    public func createTag(_ tag: TagWrite) async throws -> Tag {
        try decode(try await send("POST", "api/v2/tags/", json: tag))
    }

    public func updateTag(_ id: UUID, with tag: TagWrite) async throws -> Tag {
        try decode(try await send("PATCH", "api/v2/tags/\(id.apiString)/", json: tag))
    }

    public func deleteTag(_ id: UUID) async throws {
        _ = try await send("DELETE", "api/v2/tags/\(id.apiString)/")
    }

    // MARK: 週期預算規則（N7）

    public func tagRules(ledger: UUID) async throws -> [TagRule] {
        try await getAllPages("api/v2/tag-rules/", query: ["ledger": ledger.apiString])
    }

    public func createTagRule(_ rule: TagRuleWrite) async throws -> TagRule {
        try decode(try await send("POST", "api/v2/tag-rules/", json: rule))
    }

    public func updateTagRule(_ id: UUID, with rule: TagRuleWrite) async throws -> TagRule {
        try decode(try await send("PATCH", "api/v2/tag-rules/\(id.apiString)/", json: rule))
    }

    /// 刪除規則：已經產生的週期 tag 全部保留，變成一次性 tag（v2 §5.3）。
    public func deleteTagRule(_ id: UUID) async throws {
        _ = try await send("DELETE", "api/v2/tag-rules/\(id.apiString)/")
    }

    // MARK: 重複交易（N8）

    public func recurringRules(ledger: UUID) async throws -> [RecurringRule] {
        try await getAllPages("api/v2/recurring-rules/", query: ["ledger": ledger.apiString])
    }

    public func createRecurringRule(_ rule: RecurringRuleWrite) async throws -> RecurringRule {
        try decode(try await send("POST", "api/v2/recurring-rules/", json: rule))
    }

    public func updateRecurringRule(_ id: UUID, with rule: RecurringRuleWrite) async throws -> RecurringRule {
        try decode(try await send("PATCH", "api/v2/recurring-rules/\(id.apiString)/", json: rule))
    }

    public func deleteRecurringRule(_ id: UUID) async throws {
        _ = try await send("DELETE", "api/v2/recurring-rules/\(id.apiString)/")
    }
}
