import Foundation

// API 的資料形狀，對照後端的 frontend/openapi.yml（django-mm repo）。
// JSON 的 snake_case 由 APICoding 自動轉換，這裡的屬性一律用 camelCase。

public enum TransactionType: String, Codable, Sendable, CaseIterable, Hashable {
    case expense = "EXPENSE"
    case income = "INCOME"

    public var label: String { self == .expense ? "支出" : "收入" }
}

/// 8 個固定分類（v2-design §11）。收入和支出共用同一份。
///
/// 不叫 `Category`：Apple 平台的 ObjectiveC 模組已經有一個同名的型別。
public enum TransactionCategory: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case food = "FOOD"
    case clothing = "CLOTHING"
    case housing = "HOUSING"
    case transport = "TRANSPORT"
    case education = "EDUCATION"
    case entertainment = "ENTERTAINMENT"
    case medical = "MEDICAL"
    case other = "OTHER"

    public var id: String { rawValue }

    public var label: String {
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
}

public struct User: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var username: String
    public var email: String?

    public init(id: Int, username: String, email: String? = nil) {
        self.id = id
        self.username = username
        self.email = email
    }
}

public enum LedgerKind: String, Codable, Sendable, Hashable {
    case personal = "PERSONAL"
    case family = "FAMILY"
}

public struct LedgerTotals: Codable, Hashable, Sendable {
    public var income: Money
    public var expense: Money
    public var balance: Money
}

public struct Ledger: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var kind: LedgerKind?
    public var baseCurrency: String?
    public var timezone: String?
    public var memberCount: Int?
    public var myRole: String?

    public init(id: UUID, name: String, kind: LedgerKind? = nil, baseCurrency: String? = "TWD",
                timezone: String? = "Asia/Taipei") {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseCurrency = baseCurrency
        self.timezone = timezone
    }

    /// 帳本的時區。月份的界線、「今天」都依這個（v2-design §2.1）。
    public var timeZone: TimeZone {
        timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Asia/Taipei")!
    }

    public var currency: String { baseCurrency ?? "TWD" }
}

public struct LedgerLite: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: LedgerKind?
    public var baseCurrency: String?
    public var timezone: String?
}

public struct TagLite: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isArchived: Bool?
    public var periodStart: LocalDate?
    public var periodEnd: LocalDate?
}

/// Tag（預算）。週期 tag 每一期是一個 Tag（v2-design §5）。
public struct Tag: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var budgetAmount: Money?
    public var isArchived: Bool?
    public var periodStart: LocalDate?
    public var periodEnd: LocalDate?
    public var isPeriodic: Bool
    public var spent: Money
    public var remaining: Money?

    public init(id: UUID, name: String, budgetAmount: Money? = nil, periodStart: LocalDate? = nil,
                periodEnd: LocalDate? = nil, isPeriodic: Bool = false, spent: Money = .zero,
                remaining: Money? = nil) {
        self.id = id
        self.name = name
        self.budgetAmount = budgetAmount
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.isPeriodic = isPeriodic
        self.spent = spent
        self.remaining = remaining
    }

    /// 花費佔預算的比例（0…∞）；沒有預算時是 nil。
    public var progress: Double? {
        guard let budget = budgetAmount, budget.value > 0 else { return nil }
        return NSDecimalNumber(decimal: spent.value / budget.value).doubleValue
    }

    /// 這個 tag 能不能掛在這一天的交易上（v2-design §4.5：週期 tag 只能掛期間內的交易）。
    public func covers(_ day: LocalDate) -> Bool {
        if let start = periodStart, day < start { return false }
        if let end = periodEnd, end < day { return false }
        return true
    }
}

/// 從 API 讀回來的交易。
public struct Transaction: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var description: String
    public var amount: Money?
    public var currency: String?
    public var transactionType: TransactionType
    public var category: TransactionCategory
    public var payer: User
    public var transactionDate: Date
    public var notes: String?
    public var ledger: LedgerLite
    public var originalAmount: Money?
    public var originalCurrency: String?
    public var exchangeRate: Money?
    public var tags: [TagLite]
    public var recurringRule: UUID?
}

/// 建立交易時送出的內容（`POST /api/v2/transactions/`、parse job 的 confirm）。
///
/// `id` 由手機產生：網路斷掉後重送，後端會認出是同一筆，不會建立兩次（ios-design §3.1）。
public struct TransactionInput: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var ledgerId: UUID
    public var description: String
    public var transactionType: TransactionType
    public var category: TransactionCategory
    public var transactionDate: Date
    /// 帳本 base currency 的金額。外幣交易可以只給 `originalAmount`，由後端用帳本匯率換算。
    public var amount: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?
    public var notes: String?
    public var tagIds: [UUID]

    public init(id: UUID = UUID(), ledgerId: UUID, description: String,
                transactionType: TransactionType = .expense, category: TransactionCategory,
                transactionDate: Date, amount: Money? = nil, originalAmount: Money? = nil,
                originalCurrency: String? = nil, notes: String? = nil, tagIds: [UUID] = []) {
        self.id = id
        self.ledgerId = ledgerId
        self.description = description
        self.transactionType = transactionType
        self.category = category
        self.transactionDate = transactionDate
        self.amount = amount
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.notes = notes
        self.tagIds = tagIds
    }

    /// 畫面上顯示的金額：有 base currency 金額就用它，否則顯示原幣。
    public var displayAmount: (Money, String?)? {
        if let amount { return (amount, nil) }
        if let originalAmount { return (originalAmount, originalCurrency) }
        return nil
    }
}

/// 修改交易時送出的內容（`PATCH /api/v2/transactions/{id}/`）。
///
/// 和 `TransactionInput` 一樣，但不帶 `id`（id 在網址裡，再送一次會被唯一性檢查擋掉）。
/// 備註清空時要明確送空字串，只是省略的話後端會保留舊的。
/// 外幣的換算由後端決定（v2 §4.3）：沒送 `amount` 時用原幣金額和既有的匯率重算。
public struct TransactionPatch: Encodable, Sendable {
    public var ledgerId: UUID
    public var description: String
    public var transactionType: TransactionType
    public var category: TransactionCategory
    public var transactionDate: Date
    public var amount: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?
    public var notes: String
    public var tagIds: [UUID]

    public init(_ input: TransactionInput) {
        ledgerId = input.ledgerId
        description = input.description
        transactionType = input.transactionType
        category = input.category
        transactionDate = input.transactionDate
        amount = input.amount
        originalAmount = input.originalAmount
        originalCurrency = input.originalCurrency
        notes = input.notes ?? ""
        tagIds = input.tagIds
    }
}

public struct Paginated<Item: Codable & Sendable>: Codable, Sendable {
    public var count: Int
    public var next: String?
    public var previous: String?
    public var results: [Item]
}

public struct CategorySummaryItem: Codable, Hashable, Sendable {
    public var key: TransactionCategory
    public var name: String
    /// 淨額：支出 − 收入（退款會讓它變少，甚至變負數）。
    public var netAmount: Money
}

public struct AuthTokens: Codable, Hashable, Sendable {
    public var access: String
    public var refresh: String

    public init(access: String, refresh: String) {
        self.access = access
        self.refresh = refresh
    }
}

// MARK: - 解析工作（ios-design §2.2）

public enum ParseSource: String, Codable, Sendable, Hashable {
    case manual
    case voice
    case receipt

    public var label: String {
        switch self {
        case .manual: "文字"
        case .voice: "語音"
        case .receipt: "照片"
        }
    }
}

public enum ParseJobStatus: String, Codable, Sendable, Hashable {
    case queued = "QUEUED"
    case running = "RUNNING"
    case done = "DONE"
    case failed = "FAILED"
    case confirmed = "CONFIRMED"
    case discarded = "DISCARDED"

    /// 還在等後端解析。
    public var isPending: Bool { self == .queued || self == .running }
}

/// LLM 解析出來、還沒確認的一筆。使用者可以修改後再確認。
public struct ParsedDraft: Codable, Hashable, Sendable {
    public var description: String
    public var transactionType: TransactionType
    public var transactionDate: Date
    public var category: TransactionCategory
    public var notes: String
    public var originalAmount: Money?
    public var originalCurrency: String?
    public var exchangeRate: Money?
    /// base currency 的金額。外幣而帳本沒有匯率時是 nil，要使用者自己填。
    public var amount: Money?
    public var ledgerId: UUID

    /// 變成要送出的交易。`id` 要在使用者第一次看到時就決定好，之後重送都用同一個。
    public func input(id: UUID = UUID(), tagIds: [UUID] = []) -> TransactionInput {
        TransactionInput(
            id: id, ledgerId: ledgerId, description: description,
            transactionType: transactionType, category: category,
            transactionDate: transactionDate, amount: amount,
            originalAmount: originalAmount, originalCurrency: originalCurrency,
            notes: notes.isEmpty ? nil : notes, tagIds: tagIds)
    }
}

public struct ParseJob: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var ledgerId: UUID
    public var source: ParseSource
    public var text: String
    public var capturedAt: Date
    public var status: ParseJobStatus
    public var drafts: [ParsedDraft]
    public var error: String
    public var transactionIds: [UUID]
    public var createdAt: Date
    public var updatedAt: Date
}
