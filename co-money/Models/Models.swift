// Models.swift
// co-money
// Data models matching the codai8.com API schema
// 数据模型，对应 codai8.com API 返回的 JSON 结构

import Foundation

// MARK: - User
/// 用户基础信息模型 | User model for storing basic user information
///
/// 用途：表示系统中的一个用户，包含用户ID、用户名和邮箱
/// Purpose: Represents a user in the system with their ID, username, and email
///
/// SwiftUI概念：
/// - Codable: 使该结构体可以自动与JSON数据互转（decode from API, encode to API）
/// - Identifiable: 让结构体可用于 List, ForEach 等SwiftUI组件，id作为唯一标识符
/// - Hashable: 使该模型可用作 Dictionary 的键或 Set 的元素
///
/// API来源：登录API返回用户对象，其他涉及用户的API也会返回此结构体
struct User: Codable, Identifiable, Hashable {
    /// 用户唯一标识符 | User's unique identifier
    let id: Int

    /// 用户名 | User's username (display name)
    let username: String

    /// 邮箱地址，可选值（某些API响应可能不返回）
    /// Email address, optional (some API responses may not include it)
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id, username, email
    }

    init(id: Int, username: String, email: String?) {
        self.id = id
        self.username = username
        self.email = email
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = intId
        } else if let stringId = try? c.decode(String.self, forKey: .id), let intId = Int(stringId) {
            id = intId
        } else {
            id = 0
        }
        username = (try? c.decode(String.self, forKey: .username)) ?? "Unknown"
        email = try? c.decodeIfPresent(String.self, forKey: .email) ?? nil
    }
}

// MARK: - Profile
/// 用户个人资料模型 | User profile model with preferences and metadata
///
/// 用途：存储用户的详细信息，包括头像、默认共享账户和默认货币
/// Purpose: Stores user's detailed information including profile image,
///          default shared accounts, and default currency preference
///
/// SwiftUI概念：
/// - Codable: 需要自定义 init(from:) 和 encode(to:) 方法来处理API特殊情况
///   (API可能返回null，但我们需要将其转换为空数组)
/// - CodingKeys: 将Swift属性名与JSON字段名映射，例如 defaultSharedAccounts
///   对应 API 的 default_shared_accounts（下划线命名约定）
///
/// API来源：GET /api/profile/ 返回用户的个人资料
struct Profile: Codable, Identifiable {
    /// 个人资料唯一标识符 | Profile's unique identifier
    let id: Int

    /// 关联的用户对象 | Associated User object
    /// 包含用户基础信息，通过嵌套的JSON对象返回
    let user: User

    /// 用户头像URL | User's profile image URL, optional
    var image: String?

    /// 用户的默认共享账户列表（账户ID数组）
    /// Default shared accounts for quick access (array of account IDs)
    /// API可能返回null或省略此字段，自定义init处理为空数组
    /// Custom init converts null/missing values to empty array
    var defaultSharedAccounts: [String]

    /// 用户偏好的默认货币代码（例如 "USD", "CNY"）
    /// User's preferred default currency code (e.g., "USD", "CNY"), optional
    var defaultCurrency: String?

    /// CodingKeys用于声明JSON字段与Swift属性的映射关系
    /// Maps Swift property names to JSON field names from the API
    /// 这是必要的，因为API使用snake_case（下划线），Swift使用camelCase（驼峰）
    enum CodingKeys: String, CodingKey {
        case id, user, image
        case defaultSharedAccounts = "default_shared_accounts"  // API字段名: "default_shared_accounts"
        case defaultCurrency = "default_currency"               // API字段名: "default_currency"
    }

    /// 自定义解码初始化器 | Custom decoding initializer
    /// 用途：处理API返回的JSON数据，特别是处理null值的特殊情况
    /// Purpose: Parse JSON from API response, especially handling null values
    ///
    /// 为什么需要自定义init？
    /// Why custom init? The API may return null for defaultSharedAccounts,
    /// but we want to treat it as an empty array rather than nil
    init(from decoder: Decoder) throws {
        // 创建容器来访问JSON数据 | Create a container to access JSON fields
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // 解码必需字段 | Decode required fields
        id                   = try c.decode(Int.self, forKey: .id)
        user                 = try c.decode(User.self, forKey: .user)

        // 解码可选字段 | Decode optional fields
        // decodeIfPresent 返回nil如果字段不存在，?? nil 允许尝试解码失败
        image                = try? c.decodeIfPresent(String.self, forKey: .image) ?? nil

        // API可能返回null或省略此字段（当没有默认设置时）
        // 使用 ?? [] 确保即使API返回null也转换为空数组，而不是nil
        // The API may return null or omit this field when no defaults are set
        defaultSharedAccounts = (try? c.decodeIfPresent([String].self, forKey: .defaultSharedAccounts)) ?? []

        // 相同的处理逻辑用于货币字段 | Similar handling for currency field
        defaultCurrency       = try? c.decodeIfPresent(String.self, forKey: .defaultCurrency) ?? nil
    }

    /// 自定义编码方法 | Custom encoding method
    /// 用途：将Swift模型对象转换为JSON数据，发送到API
    /// Purpose: Convert Swift model to JSON format for API requests
    func encode(to encoder: Encoder) throws {
        // 创建编码容器 | Create encoding container
        var c = encoder.container(keyedBy: CodingKeys.self)

        // 编码所有字段 | Encode all fields
        try c.encode(id,                     forKey: .id)
        try c.encode(user,                   forKey: .user)
        // encodeIfPresent 只在值非nil时编码该字段
        // encodeIfPresent only encodes the field if value is not nil
        try c.encodeIfPresent(image,         forKey: .image)
        try c.encode(defaultSharedAccounts,  forKey: .defaultSharedAccounts)
        try c.encodeIfPresent(defaultCurrency, forKey: .defaultCurrency)
    }
}

// MARK: - Category
/// 交易分类模型 | Transaction category model
///
/// 用途：表示一个交易分类，用于将交易标记和分组
/// Purpose: Represents a transaction category for organizing and filtering transactions
///
/// SwiftUI概念：
/// - CodingKeys: 处理 created_by 和 created_at 的snake_case到camelCase转换
/// - Hashable: 使Category可用于Set集合和Dictionary键
///
/// API来源：GET /api/categories/ 返回分类列表
struct Category: Codable, Identifiable, Hashable {
    /// 分类唯一标识符（通常是UUID）| Category's unique identifier (usually UUID)
    let id: String

    /// 分类名称，可修改 | Category name, mutable
    var name: String

    /// 分类图标（SF Symbols名称或emoji）| Category icon (SF Symbol name or emoji)
    var icon: String?

    /// 创建此分类的用户ID | User ID who created this category
    let createdBy: Int?

    /// 分类创建时间 | Timestamp when category was created
    let createdAt: Date

    /// JSON字段名映射 | Maps property names to JSON field names
    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case createdBy = "created_by"      // API: "created_by"
        case createdAt = "created_at"      // API: "created_at"
    }
}

// MARK: - Transaction
/// 交易记录模型 | Transaction record model
///
/// 用途：表示一条交易记录，包含金额、类型、日期、分类、参与者等详细信息
/// Purpose: Represents a single transaction with all relevant details
///
/// 数据流：用户创建交易 → CreateTransactionRequest → API → Transaction响应
/// Data flow: User creates transaction → CreateTransactionRequest → API → Transaction response
///
/// SwiftUI概念：
/// - Identifiable: 使Transaction可用于List和ForEach中
/// - amount 是 String 而非 Double，原因是精度问题（金融数据应该用Decimal或String）
/// - Codable: 自动处理JSON序列化/反序列化
///
/// API来源：GET /api/transactions/, POST /api/transactions/ 创建交易
struct Transaction: Codable, Identifiable {
    /// 交易唯一标识符 | Transaction's unique identifier
    let id: String

    /// 交易描述（例如"买咖啡"）| Transaction description (e.g., "Coffee")
    var description: String

    /// 交易金额（存储为字符串以保持精度）
    /// Transaction amount (stored as String to preserve precision for financial data)
    var amount: String

    /// 交易货币代码（例如 "USD", "CNY"）| Currency code (e.g., "USD", "CNY")
    var currency: String?

    /// 交易类型：收入或支出 | Transaction type: INCOME or EXPENSE
    var transactionType: TransactionType

    /// 交易分类名称 | Category label stored on the transaction
    let category: String?

    /// 进行交易的用户 | User who made this transaction
    let payer: User

    /// 交易日期 | Date when transaction occurred
    var transactionDate: Date

    /// 此交易关联的共享账户列表 | List of shared accounts involved in this transaction
    let accounts: [SharedAccountLite]

    /// 账户ID列表（用于创建/更新时指定哪些账户受影响）
    /// Account IDs involved (used when creating/updating to specify which accounts are affected)
    var accountIds: [String]?

    /// 交易备注 | Transaction notes/memo
    var notes: String?

    /// JSON字段映射 | JSON field name mappings
    enum CodingKeys: String, CodingKey {
        case id, description, amount, currency, category, payer, accounts, notes
        case transactionType = "transaction_type"    // API: "transaction_type"
        case transactionDate = "transaction_date"    // API: "transaction_date"
        case accountIds = "account_ids"              // API: "account_ids"
    }

    /// 自訂解碼器：容許 backend 對部分欄位回傳 null、數字或簡化格式。
    /// Custom decoder: accepts nulls, numbers, and trimmed response shapes from the backend.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let stringId = try? c.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = UUID().uuidString
        }

        description = (try? c.decode(String.self, forKey: .description)) ?? "未命名交易"

        if let str = try? c.decode(String.self, forKey: .amount) {
            amount = str
        } else if let decimal = try? c.decode(Decimal.self, forKey: .amount) {
            amount = NSDecimalNumber(decimal: decimal).stringValue
        } else if let num = try? c.decode(Double.self, forKey: .amount) {
            amount = String(format: "%.2f", num)
        } else {
            amount = "0"
        }

        currency = try? c.decodeIfPresent(String.self, forKey: .currency)
        transactionType = (try? c.decode(TransactionType.self, forKey: .transactionType)) ?? .expense
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        payer = (try? c.decode(User.self, forKey: .payer)) ?? User(id: 0, username: "Unknown", email: nil)
        transactionDate = (try? c.decode(Date.self, forKey: .transactionDate)) ?? Date()
        accounts = (try? c.decodeIfPresent([SharedAccountLite].self, forKey: .accounts)) ?? []
        accountIds = try? c.decodeIfPresent([String].self, forKey: .accountIds)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// 交易类型枚举 | Transaction type enum
///
/// 用途：表示交易的方向：收入或支出
/// Purpose: Represents the direction of a transaction
///
/// SwiftUI概念：
/// - Enum with raw values: 枚举关联字符串值，使其可Codable
///   Enum with raw values: Raw strings map to API values, making it Codable
/// - CaseIterable: 使枚举可迭代，用于Picker选项列表
/// - 计算属性（Computed Properties）: localizedName 和 icon 提供UI展示所需的本地化文本和图标
///
/// 用法示例：
/// if transaction.transactionType == .expense {
///     // 显示支出相关UI
/// }
enum TransactionType: String, Codable, CaseIterable {
    /// 收入交易 | Income transaction
    case income = "INCOME"

    /// 支出交易 | Expense transaction
    case expense = "EXPENSE"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).uppercased()
        self = TransactionType(rawValue: value) ?? .expense
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// 本地化显示名称（中英文）| Localized display name (Chinese and English)
    /// 此属性在UI中用于向用户显示交易类型，支持双语显示
    /// Used in UI to show transaction type to users with bilingual support
    var localizedName: String {
        switch self {
        case .income: return "收入 Income"
        case .expense: return "支出 Expense"
        }
    }

    /// SF Symbols 图标名称 | SF Symbols icon name
    /// 用于在SwiftUI中显示相应的系统图标
    /// Used in SwiftUI to display corresponding system icons
    var icon: String {
        switch self {
        case .income: return "arrow.down.circle.fill"    // 向下箭头表示收入
        case .expense: return "arrow.up.circle.fill"     // 向上箭头表示支出
        }
    }
}

// MARK: - Shared Account
/// 共享账户模型 | Shared account model
///
/// 用途：表示一个可被多个用户共享的财务账户（例如共同储蓄账户）
/// Purpose: Represents a financial account that can be shared among multiple users
///
/// SwiftUI概念：
/// - Identifiable: 使其可用于List/ForEach迭代
/// - 注意：API返回 summaries 作为原始字符串，而非JSON对象
///   Note: API returns `summaries` as raw string, not JSON object
///
/// API来源：GET /api/shared-accounts/ 获取用户的所有共享账户
struct SharedAccount: Codable, Identifiable {
    /// 账户唯一标识符 | Account's unique identifier
    let id: String

    /// 账户名称（例如"家庭储蓄账户"）| Account name (e.g., "Family Savings Account")
    var name: String

    /// 账户所有者的用户ID | User ID of the account owner
    let owner: Int

    /// 账户创建时间 | Timestamp when account was created
    let createdAt: Date

    /// 账户描述 | Account description, optional
    var description: String?

    /// 注意：API返回 summaries 作为原始字符串（不是JSON对象）
    /// 收入/支出/余额统计由客户端在 TransactionViewModel.summary(forAccountId:) 中计算
    /// Note: API returns `summaries` as a raw string (not JSON object); we compute
    /// income/expense/balance client-side via TransactionViewModel.summary(forAccountId:).

    /// JSON字段映射 | JSON field name mappings
    enum CodingKeys: String, CodingKey {
        case id, name, owner, description
        case createdAt = "created_at"  // API: "created_at"
    }
}

/// 分页的账户列表模型 | Paginated account list model
///
/// 用途：处理API分页响应，包含总数、前后分页链接和账户数组
/// Purpose: Handles paginated API responses with count, pagination links, and results
///
/// API来源：GET /api/shared-accounts/ （通常返回分页数据）
/// 用法：当列表很长时，API不会一次性返回所有结果，而是通过分页加载
struct PaginatedAccountList: Codable {
    /// 总账户数 | Total number of accounts in the system
    let count:    Int?

    /// 下一页的API链接 | URL to fetch next page of results
    let next:     String?

    /// 上一页的API链接 | URL to fetch previous page of results
    let previous: String?

    /// 当前页的账户列表 | List of accounts in current page
    let results:  [SharedAccount]
}

/// 精简共享账户模型 | Lightweight shared account model
///
/// 用途：在某些API响应中，完整的SharedAccount信息不总是需要的
/// 这个"Lite"版本只包含关键信息，用于减少网络传输大小
/// Purpose: Lightweight version used in API responses where full account details aren't needed
/// Reduces network payload size
///
/// 与SharedAccount的区别：lite版本通常出现在关联的对象中，不包含账户的完整统计数据
struct SharedAccountLite: Codable, Identifiable {
    /// 账户唯一标识符 | Account's unique identifier
    let id: String

    /// 账户名称 | Account name
    var name: String

    /// 账户所有者的用户ID | User ID of account owner
    /// Optional: parse responses only return id + name, not full account details
    let owner: Int?

    /// 账户创建时间 | Timestamp when account was created
    /// Optional: parse responses only return id + name, not full account details
    let createdAt: Date?

    /// 账户描述 | Account description, optional
    var description: String?

    /// JSON字段映射 | JSON field name mappings
    enum CodingKeys: String, CodingKey {
        case id, name, owner, description
        case createdAt = "created_at"  // API: "created_at"
    }
}

// MARK: - Membership
/// 账户成员模型 | Account membership model
///
/// 用途：表示一个用户在某个共享账户中的成员身份和权限角色
/// Purpose: Represents a user's membership and role in a shared account
///
/// 数据关系：一个Membership连接一个User和一个SharedAccount
/// Relationship: One Membership connects one User and one SharedAccount
///
/// API来源：GET /api/memberships/ 获取当前用户所在的所有账户的成员信息
struct Membership: Codable, Identifiable {
    /// 成员身份唯一标识符 | Membership's unique identifier
    let id: String

    /// 该成员身份关联的用户 | User who has this membership
    let user: User

    /// 账户ID（该用户是该账户的成员）| Account ID this membership belongs to
    let account: String

    /// 用户在此账户中的角色（所有者、管理员或普通成员）
    /// User's role in this account (owner, admin, or member)
    var role: MembershipRole

    /// 成员身份是否活跃 | Whether this membership is active
    var isActive: Bool

    /// 用户加入该账户的时间 | Timestamp when user joined this account
    let joinedAt: Date

    /// JSON字段映射 | JSON field name mappings
    enum CodingKeys: String, CodingKey {
        case id, user, account, role
        case isActive = "is_active"  // API: "is_active"
        case joinedAt = "joined_at"  // API: "joined_at"
    }
}

/// 成员身份角色枚举 | Membership role enum
///
/// 用途：定义用户在共享账户中的权限级别
/// Purpose: Defines permission levels for users in shared accounts
///
/// 权限层级（从高到低）| Permission hierarchy (highest to lowest):
/// - OWNER: 完全控制，可管理其他成员 | Full control, can manage other members
/// - ADMIN: 几乎完全控制，受某些限制 | Nearly full control with some restrictions
/// - MEMBER: 基础权限，只能查看和创建交易 | Basic permissions, can view and create transactions
enum MembershipRole: String, Codable {
    /// 账户所有者，拥有最高权限 | Account owner with highest permissions
    case owner = "OWNER"

    /// 管理员，拥有大部分管理权限 | Administrator with most management permissions
    case admin = "ADMIN"

    /// 普通成员，基础权限 | Regular member with basic permissions
    case member = "MEMBER"
}

// MARK: - Invitation
/// 账户邀请模型 | Account invitation model
///
/// 用途：表示一个邀请某人加入共享账户的邀请记录
/// Purpose: Represents an invitation for a user to join a shared account
///
/// 邀请流程：
/// 1. 账户所有者创建邀请 → POST /api/invitations/
/// 2. 被邀请者接收邀请 → API返回Invitation对象
/// 3. 被邀请者接受或拒绝 → PATCH /api/invitations/{id}/
///
/// API来源：GET /api/invitations/, POST /api/invitations/, PATCH /api/invitations/{id}/
struct Invitation: Codable, Identifiable {
    /// 邀请唯一标识符 | Invitation's unique identifier
    let id: String

    /// 被邀请加入的账户ID | UUID of the SharedAccount being invited to
    var account: String

    /// 发送邀请的用户（在GET响应中返回）
    /// The user who sent the invite (returned in GET response)
    let inviter: User?

    /// 被邀请的用户对象，可能为nil
    /// 原因：API将 invitee 标记为仅写入，某些响应不包含此字段
    /// The user being invited, may be nil. Reason: API marks `invitee` as write-only
    let invitee: User?

    /// 被邀请者的用户名（某些API版本直接返回用户名字符串）
    /// Invitee username string (some API versions return raw username instead of User object)
    let inviteeUsername: String?

    /// 邀请的当前状态（待处理、已接受、已拒绝）
    /// Current status of the invitation (PENDING, ACCEPTED, or DECLINED)
    let status: InvitationStatus?

    /// 邀请创建时间 | Timestamp when invitation was created
    let createdAt: Date

    /// JSON字段映射 | JSON field name mappings
    enum CodingKeys: String, CodingKey {
        case id, account, inviter, invitee, status
        case inviteeUsername = "invitee_username"  // API: "invitee_username"
        case createdAt = "created_at"              // API: "created_at"
    }

    /// 被邀请者的显示名称（尽力取值）
    /// Best-effort display name for the invitee
    ///
    /// 逻辑：优先使用User对象中的username，否则使用inviteeUsername字符串
    /// Logic: Prefers username from User object, falls back to inviteeUsername string
    var inviteeDisplay: String? {
        invitee?.username ?? inviteeUsername
    }
}

/// 邀请状态枚举 | Invitation status enum
///
/// 用途：跟踪邀请的处理状态
/// Purpose: Tracks the processing status of an invitation
enum InvitationStatus: String, Codable {
    /// 邀请待处理，被邀请者尚未响应 | Invitation pending, waiting for response
    case pending = "PENDING"

    /// 被邀请者已接受邀请 | Invitee accepted the invitation
    case accepted = "ACCEPTED"

    /// 被邀请者已拒绝邀请 | Invitee declined the invitation
    case declined = "DECLINED"
}

// MARK: - Paginated Lists
/// 分页的交易列表模型 | Paginated transaction list model
///
/// 用途：处理按月份分页的交易API响应
/// Purpose: Handles paginated transaction API responses organized by month
///
/// 特殊功能：提供前一个月和下一个月的分页链接，用于实现月度视图导航
/// Special feature: Provides previous/next month URLs for calendar-style navigation
///
/// API来源：GET /api/transactions/ （按月份分页）
struct PaginatedTransactionList: Codable {
    /// 当前月份字符串（例如 "2024-01"）| Current month string (e.g., "2024-01")
    let currentMonth: String?

    /// 上一个月的交易列表API链接 | URL to fetch transactions for previous month
    let previousMonthUrl: String?

    /// 下一个月的交易列表API链接 | URL to fetch transactions for next month
    let nextMonthUrl: String?

    /// 当前月份的交易总数 | Total count of transactions in current month
    let count: Int?

    /// 当前月份的交易列表 | List of transactions in current month
    let results: [Transaction]

    /// JSON字段映射 | JSON field name mappings
    enum CodingKeys: String, CodingKey {
        case count, results, next, previous
        case currentMonth = "current_month"        // API: "current_month"
        case previousMonthUrl = "previous_month_url"  // API: "previous_month_url"
        case nextMonthUrl = "next_month_url"       // API: "next_month_url"
    }

    init(currentMonth: String?, previousMonthUrl: String?, nextMonthUrl: String?, count: Int?, results: [Transaction]) {
        self.currentMonth = currentMonth
        self.previousMonthUrl = previousMonthUrl
        self.nextMonthUrl = nextMonthUrl
        self.count = count
        self.results = results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentMonth = try? c.decodeIfPresent(String.self, forKey: .currentMonth)
        previousMonthUrl = (try? c.decodeIfPresent(String.self, forKey: .previousMonthUrl))
            ?? (try? c.decodeIfPresent(String.self, forKey: .previous))
        nextMonthUrl = (try? c.decodeIfPresent(String.self, forKey: .nextMonthUrl))
            ?? (try? c.decodeIfPresent(String.self, forKey: .next))
        count = try? c.decodeIfPresent(Int.self, forKey: .count)
        results = (try? c.decode([Transaction].self, forKey: .results)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(currentMonth, forKey: .currentMonth)
        try c.encodeIfPresent(previousMonthUrl, forKey: .previousMonthUrl)
        try c.encodeIfPresent(nextMonthUrl, forKey: .nextMonthUrl)
        try c.encodeIfPresent(count, forKey: .count)
        try c.encode(results, forKey: .results)
    }
}

/// 分页的分类列表模型 | Paginated category list model
///
/// 用途：处理分类API的分页响应
/// Purpose: Handles paginated API responses for categories
///
/// 标准分页格式：count（总数）、next（下一页链接）、previous（上一页链接）、results（结果）
struct PaginatedCategoryList: Codable {
    /// 分类总数 | Total number of categories
    let count: Int

    /// 下一页的API链接 | URL to fetch next page of categories
    let next: String?

    /// 上一页的API链接 | URL to fetch previous page of categories
    let previous: String?

    /// 当前页的分类列表 | List of categories in current page
    let results: [Category]
}

// MARK: - Auth
/// 令牌对模型 | Token pair model
///
/// 用途：存储登录成功后的访问令牌和刷新令牌
/// Purpose: Stores access and refresh tokens received after successful login
///
/// 令牌说明：
/// - access: 用于认证API请求，有较短的有效期（通常1小时）
/// - refresh: 用于刷新access令牌，有较长的有效期（通常1个月或更长）
///
/// Token explanation:
/// - access: Used to authenticate API requests, short expiration (typically 1 hour)
/// - refresh: Used to refresh access token, longer expiration (typically 1 month+)
///
/// API来源：POST /api/token/ （登录）
struct TokenPair: Codable {
    /// 访问令牌，用于API认证 | Access token for API authentication
    let access: String

    /// 刷新令牌，用于获取新的访问令牌 | Refresh token for obtaining new access token
    let refresh: String
}

/// 令牌刷新响应模型 | Token refresh response model
///
/// 用途：处理刷新令牌后的API响应
/// Purpose: Handles API response when refreshing token
///
/// API来源：POST /api/token/refresh/ （刷新令牌）
struct TokenRefreshResponse: Codable {
    /// 新的访问令牌 | New access token
    let access: String

    /// 新的刷新令牌（可选，某些API实现不更新）
    /// New refresh token (optional, some API implementations don't update it)
    let refresh: String?
}

// MARK: - Transaction Parse Request
/// 交易解析源枚举 | Transaction parse source enum
///
/// 用途：指示交易数据来自哪个来源（语音、收据或手动输入）
/// Purpose: Indicates the source of transaction data for parsing
///
/// 用法场景：
/// - voice: 用户通过语音输入交易信息
/// - receipt: 用户上传收据照片，应用OCR识别
/// - manual: 用户手动输入交易
enum ParseSource: String, Codable {
    /// 语音输入 | Voice input
    case voice   = "voice"

    /// 收据识别（OCR）| Receipt recognition (OCR)
    case receipt  = "receipt"

    /// 手动输入 | Manual input
    case manual   = "manual"
}

/// 交易解析请求模型 | Transaction parse request model
///
/// 用途：将用户输入的原始文本发送给API的AI解析功能
/// Purpose: Sends raw user input text to API's AI parsing service
///
/// 用法示例：
/// let request = TransactionParseRequest(
///     text: "买了三杯咖啡，花了30块钱",
///     source: .voice
/// )
/// // 将其发送给API，API会返回解析后的Transaction信息
///
/// API来源：POST /api/transactions/parse/ （AI解析交易）
struct TransactionParseRequest: Codable {
    /// 待解析的文本 | Raw text to parse
    /// 例如："昨天买咖啡花了15元" | e.g., "Bought coffee for 15 yuan yesterday"
    let text: String

    /// 文本来源 | Source of the text
    let source: ParseSource?
}

// MARK: - Create Transaction
/// 创建交易请求模型 | Create transaction request model
///
/// 用途：用户创建新交易时发送给API的数据结构
/// Purpose: Data structure sent to API when user creates a new transaction
///
/// 数据流：用户输入 → CreateTransactionRequest → POST /api/transactions/ → API返回Transaction
/// Data flow: User input → CreateTransactionRequest → POST /api/transactions/ → API returns Transaction
///
/// 与Transaction模型的区别：
/// - CreateTransactionRequest 用于POST请求（创建新交易）
/// - Transaction 用于API响应（已创建的交易）
/// Difference:
/// - CreateTransactionRequest: Used for POST request (creating new)
/// - Transaction: Used for API response (already created)
struct CreateTransactionRequest: Codable {
    /// 交易描述 | Transaction description
    var description: String

    /// 交易金额 | Transaction amount
    var amount: String

    /// 交易货币代码 | Currency code
    var currency: String?

    /// 交易类型（INCOME 或 EXPENSE）| Transaction type (INCOME or EXPENSE)
    var transactionType: TransactionType

    /// 交易日期（ISO8601格式的字符串，例如 "2024-01-15"）
    /// Transaction date in ISO8601 string format (e.g., "2024-01-15")
    /// 注意：这是String而非Date，因为需要与API的日期格式完全匹配
    var transactionDate: String

    /// 交易关联的账户ID列表 | List of account IDs involved in this transaction
    var accountIds: [String]

    /// 分類文字標籤 | Plain-text category label
    var category: String?

    /// 交易备注 | Transaction notes
    var notes: String?

    /// JSON字段映射 | JSON field name mappings
    enum CodingKeys: String, CodingKey {
        case description, amount, currency, category, notes
        case transactionType = "transaction_type"    // API: "transaction_type"
        case transactionDate = "transaction_date"    // API: "transaction_date"
        case accountIds = "account_ids"              // API: "account_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .description)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encode(transactionType, forKey: .transactionType)
        try container.encode(transactionDate, forKey: .transactionDate)
        try container.encode(accountIds, forKey: .accountIds)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}
