// AccountService.swift
// co-money
// 账户服务 | Account Service
// 管理共享账户和邀请的CRUD操作
// Manages shared account and invitation CRUD operations

import Foundation

// MARK: - Account Service
// 账户服务 | Account Service
// 单例模式，处理所有共享账户和邀请相关的API调用
// Singleton pattern, handles all shared account and invitation-related API calls
//
// 共享账户概念 | Shared Account Concept:
// 允许多个用户共享一个账户并分享账户中的所有交易
// Allows multiple users to share one account and view all transactions in it
// 适用场景：家庭共享开支、情侣分摊费用、室友账单等
// Use cases: family shared expenses, couple bill-splitting, roommate bills, etc.
//
// 职责 | Responsibilities:
// 1. 获取共享账户列表 | Fetch shared accounts
// 2. 创建新的共享账户 | Create new shared account
// 3. 删除共享账户 | Delete shared account
// 4. 管理邀请（发送、接受、拒绝）| Manage invitations (send, accept, decline)
//
// HTTP 接口 | HTTP endpoints:
// GET    /accounts/                      - 获取所有账户 | Get all accounts
// GET    /accounts/{id}/                 - 获取单个账户 | Get single account
// POST   /accounts/                      - 创建新账户 | Create new account
// DELETE /accounts/{id}/                 - 删除账户 | Delete account
// POST   /invitations/                   - 发送邀请 | Send invitation
// GET    /invitations/                   - 获取已发送邀请 | Get sent invitations
// GET    /invitations/my_invitations/    - 获取已接收邀请 | Get received invitations
// POST   /invitations/{id}/accept/       - 接受邀请 | Accept invitation
// POST   /invitations/{id}/decline/      - 拒绝邀请 | Decline invitation
final class AccountService {
    // MARK: Singleton Pattern
    static let shared = AccountService()
    private init() {}

    private let client = APIClient.shared

    // MARK: - Shared Accounts
    // 共享账户管理 | Shared Account Management

    /// 获取所有共享账户 | Get all shared accounts
    /// 返回当前用户参与的所有共享账户
    /// Returns all shared accounts current user participates in
    ///
    /// 请求方法 | Request method:
    /// HTTP GET /accounts/
    ///
    /// 响应格式兼容性 | Response format compatibility:
    /// 后端使用 DRF，可能返回两种格式：
    /// Backend uses DRF, might return two formats:
    /// 1. 分页格式：{ "count": 5, "results": [...] }
    /// 2. 纯数组：[{ account1 }, { account2 }, ...]
    ///
    /// 由于API设计可能不一致，我们尝试两种格式
    /// Due to potential API design inconsistency, we try both formats
    func getAccounts() async throws -> [SharedAccount] {
        // 尝试分页格式 | Try paginated format
        // DRF 通常返回分页格式（包含元数据）
        // DRF usually returns paginated format (with metadata)
        if let paginated: PaginatedAccountList = try? await client.request(path: "/accounts/") {
            return paginated.results
        }

        // 如果分页格式失败，尝试纯数组 | If paginated fails, try plain array
        // 有些简化的API可能直接返回数组
        // Some simplified APIs might return array directly
        return try await client.request(path: "/accounts/")
    }

    /// 获取单个账户 | Get single account
    /// 按ID获取单个账户的详细信息
    /// Get detailed info of single account by ID
    ///
    /// 请求方法 | Request method:
    /// HTTP GET /accounts/{id}/
    func getAccount(id: String) async throws -> SharedAccount {
        return try await client.request(path: "/accounts/\(id)/")
    }

    /// 创建新共享账户 | Create new shared account
    /// 创建一个新的共享账户，创建者自动成为所有者
    /// Create new shared account, creator automatically becomes owner
    ///
    /// 请求方法 | Request method:
    /// HTTP POST /accounts/
    ///
    /// 请求体格式 | Request body format:
    /// {
    ///   "name": "家庭账户",
    ///   "description": "记录全家的支出"  // 可选 | optional
    /// }
    ///
    /// 创建流程 | Creation flow:
    /// 1. 用户输入账户名称和描述 | User enters account name and description
    /// 2. 发送 POST 请求创建账户 | Send POST request to create account
    /// 3. 服务器创建新账户并将创建者添加为成员 | Server creates account and adds creator as member
    /// 4. 返回创建的账户对象（包含新生成的ID）| Return created account object (with new ID)
    /// 5. 后续可以使用 inviteMember() 邀请其他用户 | Subsequently can use inviteMember() to invite others
    ///
    /// 参数 | Parameters:
    /// - name: 账户名称（必需）| Account name (required)
    /// - description: 账户描述（可选）| Account description (optional)
    func createAccount(name: String, description: String?) async throws -> SharedAccount {
        var params: [String: String] = ["name": name]
        if let description { params["description"] = description }
        let body = try client.encoder.encode(params)
        return try await client.request(path: "/accounts/", method: "POST", body: body)
    }

    /// 删除共享账户 | Delete shared account
    /// 删除一个共享账户（通常只有所有者才能删除）
    /// Delete shared account (usually only owner can delete)
    ///
    /// 请求方法 | Request method:
    /// HTTP DELETE /accounts/{id}/
    ///
    /// 删除流程 | Deletion flow:
    /// 1. 用户点击删除账户按钮 | User clicks delete account button
    /// 2. 服务器验证用户是否为账户所有者 | Server verifies user is account owner
    /// 3. 如果是所有者，删除账户及其所有交易（取决于服务器逻辑）
    ///    If owner, delete account and all its transactions (depends on server logic)
    /// 4. 否则返回403 Forbidden | Otherwise return 403 Forbidden
    ///
    /// 参数 | Parameters:
    /// - id: 要删除的账户ID | ID of account to delete
    func deleteAccount(id: String) async throws {
        try await client.requestVoid(path: "/accounts/\(id)/", method: "DELETE")
    }

    // MARK: - Invitations
    // 邀请管理 | Invitation Management
    // 邀请机制允许账户所有者邀请其他用户加入共享账户
    // Invitation mechanism allows account owner to invite other users to join shared account

    /// 邀请成员加入共享账户 | Invite member to shared account
    /// 邀请一个用户加入特定的共享账户
    /// Invite a user to join specific shared account
    ///
    /// 请求方法 | Request method:
    /// HTTP POST /invitations/
    ///
    /// 请求体格式 | Request body format:
    /// {
    ///   "account": "account-id",
    ///   "invitee": "username"
    /// }
    ///
    /// 邀请流程 | Invitation flow:
    /// 1. 账户所有者选择要邀请的用户 | Account owner selects user to invite
    /// 2. 发送 POST 请求创建邀请 | Send POST request to create invitation
    /// 3. 服务器创建邀请记录，被邀请者收到通知 | Server creates invitation, invitee gets notification
    /// 4. 被邀请者可以接受或拒绝邀请 | Invitee can accept or decline invitation
    /// 5. 接受后，被邀请者成为账户的成员 | Upon acceptance, invitee becomes member of account
    ///
    /// 参数 | Parameters:
    /// - accountId: 共享账户ID | Shared account ID
    /// - inviteeUsername: 被邀请用户的用户名 | Username of user to invite
    func inviteMember(accountId: String, inviteeUsername: String) async throws -> Invitation {
        let params = ["account": accountId, "invitee": inviteeUsername]
        let body = try client.encoder.encode(params)
        return try await client.request(path: "/invitations/", method: "POST", body: body)
    }

    /// 获取已发送的邀请 | Get sent invitations
    /// 获取当前用户发送出去的所有邀请
    /// Get all invitations sent by current user
    ///
    /// 请求方法 | Request method:
    /// HTTP GET /invitations/
    ///
    /// 响应格式兼容性 | Response format compatibility:
    /// 可能返回两种格式：
    /// Might return two formats:
    /// 1. 分页格式：{ "results": [...] }
    /// 2. 纯数组：[...]
    ///
    /// 我们使用优雅降级：
    /// We use graceful degradation:
    /// - 先尝试分页格式，提取 results 数组
    /// - Try paginated format first, extract results array
    /// - 如果失败，尝试纯数组
    /// - If fails, try plain array
    /// - 都失败则返回空列表
    /// - If both fail, return empty list
    func getSentInvitations() async throws -> [Invitation] {
        // 定义一个临时结构体用于分页格式 | Define temporary struct for paginated format
        struct InvPage: Decodable { let results: [Invitation] }

        // 尝试分页格式 | Try paginated format
        if let page: InvPage = try? await client.request(path: "/invitations/") {
            return page.results
        }

        // 尝试纯数组 | Try plain array
        if let arr: [Invitation] = try? await client.request(path: "/invitations/") {
            return arr
        }

        // 都失败，返回空列表 | Both failed, return empty
        return []
    }

    /// 获取已接收的邀请 | Get received invitations
    /// 获取当前用户接收到的所有邀请
    /// Get all invitations received by current user
    ///
    /// 请求方法 | Request method:
    /// HTTP GET /invitations/my_invitations/
    ///
    /// 响应格式兼容性 | Response format compatibility:
    /// 可能返回三种格式：
    /// Might return three formats:
    /// 1. 分页格式：{ "results": [...] }
    /// 2. 纯数组：[...]
    /// 3. 单个对象：{ Invitation 字段 } (边界情况 | edge case)
    ///
    /// 我们尝试所有三种格式，以最大化兼容性
    /// We try all three formats to maximize compatibility
    func getMyInvitations() async throws -> [Invitation] {
        struct InvPage: Decodable { let results: [Invitation] }

        // 尝试分页格式 | Try paginated format
        if let page: InvPage = try? await client.request(path: "/invitations/my_invitations/") {
            return page.results
        }

        // 尝试纯数组 | Try plain array
        if let arr: [Invitation] = try? await client.request(path: "/invitations/my_invitations/") {
            return arr
        }

        // 尝试单个对象 | Try single object
        if let single: Invitation = try? await client.request(path: "/invitations/my_invitations/") {
            return [single]
        }

        // 都失败，返回空列表 | All failed, return empty
        return []
    }

    /// 接受邀请 | Accept invitation
    /// 接受一个已接收的邀请，成为账户的成员
    /// Accept received invitation, become member of account
    ///
    /// 请求方法 | Request method:
    /// HTTP POST /invitations/{id}/accept/
    ///
    /// 接受流程 | Acceptance flow:
    /// 1. 用户在收到的邀请列表中找到邀请 | User finds invitation in received list
    /// 2. 点击"接受"按钮 | Click "Accept" button
    /// 3. 发送 POST 请求到 /invitations/{id}/accept/ | Send POST to /invitations/{id}/accept/
    /// 4. 服务器将用户添加到账户成员列表 | Server adds user to account members
    /// 5. 邀请状态更新为"已接受" | Invitation status updated to "accepted"
    /// 6. 用户现在可以访问该账户中的所有交易 | User can now access all transactions in account
    ///
    /// 参数 | Parameters:
    /// - id: 邀请ID | Invitation ID
    func acceptInvitation(id: String) async throws {
        try await client.requestVoid(path: "/invitations/\(id)/accept/", method: "POST")
    }

    /// 拒绝邀请 | Decline invitation
    /// 拒绝一个已接收的邀请
    /// Decline received invitation
    ///
    /// 请求方法 | Request method:
    /// HTTP POST /invitations/{id}/decline/
    ///
    /// 拒绝流程 | Declination flow:
    /// 1. 用户在收到的邀请列表中找到邀请 | User finds invitation in received list
    /// 2. 点击"拒绝"按钮 | Click "Decline" button
    /// 3. 发送 POST 请求到 /invitations/{id}/decline/ | Send POST to /invitations/{id}/decline/
    /// 4. 服务器将邀请标记为已拒绝 | Server marks invitation as declined
    /// 5. 邀请从列表中消失 | Invitation disappears from list
    /// 6. 用户不会添加到账户成员列表 | User not added to account members
    ///
    /// 参数 | Parameters:
    /// - id: 邀请ID | Invitation ID
    func declineInvitation(id: String) async throws {
        try await client.requestVoid(path: "/invitations/\(id)/decline/", method: "POST")
    }
}
