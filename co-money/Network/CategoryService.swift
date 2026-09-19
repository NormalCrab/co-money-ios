// CategoryService.swift
// co-money
// 类别服务 | Category Service
// 管理交易类别的CRUD操作
// Manages transaction category CRUD operations

import Foundation

// MARK: - Category Service
// 类别服务 | Category Service
// 单例模式，处理所有类别相关的API调用
// Singleton pattern, handles all category-related API calls
//
// 类别概念 | Category Concept:
// 类别是交易的分类标签，帮助用户组织和分析支出
// Categories are classification labels for transactions, help users organize and analyze expenses
// 例如：食物、交通、娱乐等 | E.g.: Food, Transportation, Entertainment, etc.
//
// 职责 | Responsibilities:
// 1. 获取所有类别 | Fetch all categories
// 2. 创建新类别 | Create new category
// 3. 删除类别 | Delete category
//
// HTTP 接口 | HTTP endpoints:
// GET    /categories/       - 获取所有类别 | Get all categories
// POST   /categories/       - 创建新类别 | Create new category
// DELETE /categories/{id}/  - 删除类别 | Delete category
final class CategoryService {
    // MARK: Singleton Pattern
    // 确保全应用只有一个类别服务实例
    // Ensures only one category service instance app-wide
    static let shared = CategoryService()
    private init() {}

    private let client = APIClient.shared

    // MARK: - Fetch All Categories

    /// 获取所有类别 | Get all categories
    /// 返回当前用户可用的所有类别列表
    /// Returns all categories available to current user
    ///
    /// 请求方法 | Request method:
    /// HTTP GET /categories/
    ///
    /// 响应格式 | Response format:
    /// 服务器使用 Django REST Framework (DRF)，返回分页格式：
    /// Server uses Django REST Framework (DRF), returns paginated format:
    /// {
    ///   "count": 10,
    ///   "next": null,
    ///   "previous": null,
    ///   "results": [
    ///     {
    ///       "id": "cat1",
    ///       "name": "食物",
    ///       "icon": "🍔",
    ///       "created_at": "2024-01-01T00:00:00Z"
    ///     },
    ///     ...
    ///   ]
    /// }
    ///
    /// 解码过程 | Decoding process:
    /// 1. APIClient 发送 GET 请求 | APIClient sends GET request
    /// 2. 返回 JSON 数据 | Server returns JSON data
    /// 3. 解码为 PaginatedCategoryList 对象 | Decode to PaginatedCategoryList object
    ///    (包含 results 数组) | (contains results array)
    /// 4. 提取并返回 results 数组（忽略分页元数据）| Extract and return results array
    ///    (ignore pagination metadata)
    func getCategories() async throws -> [Category] {
        var page: PaginatedCategoryList = try await client.request(path: "/categories/")
        var categories = page.results

        while let next = page.next {
            page = try await client.requestURL(next)
            categories.append(contentsOf: page.results)
        }

        return categories
    }

    // MARK: - Create Category

    /// 创建新类别 | Create new category
    /// 用户可以自定义创建新的类别来分类交易
    /// Users can create custom categories to classify transactions
    ///
    /// 请求方法 | Request method:
    /// HTTP POST /categories/
    ///
    /// 请求体格式 | Request body format:
    /// {
    ///   "name": "自定义类别",
    ///   "icon": "✈️"  // 可选 | optional
    /// }
    ///
    /// 创建流程 | Creation flow:
    /// 1. 用户在UI中输入类别名称 | User enters category name in UI
    /// 2. 可选选择或输入emoji图标 | Optionally select/enter emoji icon
    /// 3. 发送 POST 请求到服务器 | Send POST request to server
    /// 4. 服务器验证名称不重复，创建新类别 | Server validates name uniqueness, creates category
    /// 5. 返回创建的类别对象（包含新生成的ID）| Return created category object (with new ID)
    /// 6. 前端将新类别添加到本地列表 | Frontend adds new category to local list
    ///
    /// 参数 | Parameters:
    /// - name: 类别名称（必需）| Category name (required)
    /// - icon: emoji 图标（可选）| emoji icon (optional)
    func createCategory(name: String, icon: String?) async throws -> Category {
        // 构建请求参数 | Build request parameters
        var params: [String: String] = ["name": name]

        // 如果提供了icon，添加到参数中 | If icon provided, add to parameters
        // Swift 的可选链式调用 (optional chaining)
        // Swift's optional chaining
        if let icon { params["icon"] = icon }

        // 编码参数为JSON | Encode parameters as JSON
        let body = try client.encoder.encode(params)

        // 发送 POST 请求 | Send POST request
        // 响应包含创建的Category对象，包括新生成的ID
        // Response contains created Category object with new ID
        return try await client.request(path: "/categories/", method: "POST", body: body)
    }

    // MARK: - Delete Category

    /// 删除类别 | Delete category
    /// 删除用户创建的自定义类别
    /// Delete user-created custom categories
    ///
    /// 请求方法 | Request method:
    /// HTTP DELETE /categories/{id}/
    ///
    /// 删除流程 | Deletion flow:
    /// 1. 用户在UI中选择要删除的类别 | User selects category to delete in UI
    /// 2. 发送 DELETE 请求到 /categories/{id}/ | Send DELETE request to /categories/{id}/
    /// 3. 服务器检查该类别是否有交易关联 | Server checks if category has associated transactions
    /// 4. 如果没有交易，删除类别；如果有交易，返回错误 | If no transactions, delete; if has transactions, return error
    /// 5. 前端从列表中移除该类别 | Frontend removes category from list
    ///
    /// 错误情况 | Error cases:
    /// - 404: 类别不存在 | Category doesn't exist
    /// - 403: 无权限删除（可能是系统内置类别）| No permission (might be built-in category)
    /// - 400: 类别有关联的交易，无法删除 | Category has associated transactions, cannot delete
    ///
    /// 参数 | Parameters:
    /// - id: 要删除的类别ID | ID of category to delete
    func deleteCategory(id: String) async throws {
        // 使用 requestVoid 因为DELETE通常不返回响应体
        // Use requestVoid because DELETE usually has no response body
        // 只需检查HTTP状态码：200/204成功，4xx/5xx失败
        // Only need to check HTTP status: 200/204 success, 4xx/5xx failure
        try await client.requestVoid(path: "/categories/\(id)/", method: "DELETE")
    }
}
