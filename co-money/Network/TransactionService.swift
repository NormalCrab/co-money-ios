// TransactionService.swift
// co-money
// 交易服务 | Transaction Service
// 管理交易数据的CRUD操作和AI解析功能
// Manages transaction CRUD operations and AI parsing functionality

import Foundation

// MARK: - Transaction Service
// 交易服务 | Transaction Service
// 单例模式，处理所有交易相关的API调用
// Singleton pattern, handles all transaction-related API calls
//
// 职责 | Responsibilities:
// 1. 获取交易列表（支持分页）| Fetch transactions (supports pagination)
// 2. 创建、更新、删除交易 | Create, update, delete transactions
// 3. 获取个人交易（仅当前用户作为付款人）| Fetch personal transactions (user as payer only)
// 4. 使用AI解析文本为交易 | Use AI to parse text into transactions
//
// HTTP 方法 | HTTP Methods:
// GET    /transactions/         - 获取所有交易（分页）| Get all transactions (paginated)
// GET    /transactions/{id}/    - 获取单个交易 | Get single transaction
// POST   /transactions/         - 创建新交易 | Create new transaction
// PATCH  /transactions/{id}/    - 更新交易（部分更新）| Update transaction (partial)
// DELETE /transactions/{id}/    - 删除交易 | Delete transaction
// GET    /transactions/mine/    - 获取用户的交易 | Get user's transactions
// POST   /transaction-parsers/parse/ - AI解析文本 | AI parse text
final class TransactionService {
    // MARK: Singleton Pattern
    static let shared = TransactionService()
    private init() {}

    private let client = APIClient.shared

    // MARK: - CRUD
    // CRUD = Create, Read, Update, Delete
    // 标准的数据库操作模式，大多数服务都遵循这个模式
    // Standard database operation pattern, most services follow this

    /// 获取交易列表 | Fetch transactions
    /// 支持分页导航 | Supports pagination navigation
    ///
    /// 分页概念 | Pagination Concept:
    /// 服务器通常不会一次返回所有数据（可能有数千条交易）
    /// Server usually doesn't return all data at once (might be thousands of transactions)
    /// 而是分页返回，每页通常包含 20-50 条数据
    /// Instead returns paginated, each page typically contains 20-50 items
    ///
    /// 分页响应格式 | Pagination response format:
    /// {
    ///   "currentMonth": "2024-03",
    ///   "nextMonthUrl": "https://api.com/api/transactions/?month=2024-04",
    ///   "previousMonthUrl": "https://api.com/api/transactions/?month=2024-02",
    ///   "count": 150,
    ///   "results": [{ transaction1 }, { transaction2 }, ...]
    /// }
    ///
    /// 分页流程 | Pagination flow:
    /// 1. 初始调用不传fullURL，获取默认分页数据 | Initial call without fullURL, get default page
    /// 2. 响应包含 nextMonthUrl 链接到下一页 | Response includes nextMonthUrl link to next page
    /// 3. 用户点击"下一页"时，使用 fullURL 参数传递返回的URL | User clicks next, pass returned URL as fullURL
    /// 4. 服务器保留分页状态，返回下一页数据 | Server preserves pagination state, returns next page
    func getTransactions(fullURL: String? = nil) async throws -> PaginatedTransactionList {
        let data: Data
        if let url = fullURL {
            data = try await client.requestData(url: url)
        } else {
            let year  = Calendar.current.component(.year,  from: Date())
            let month = Calendar.current.component(.month, from: Date())
            data = try await client.requestData(path: "/transactions/?year=\(year)&month=\(month)")
        }
        return try decodeTransactionList(from: data)
    }

    /// 获取单一共用帐户的交易 | Fetch transactions for a single shared account
    /// 對應 GET /api/accounts/{id}/transactions/?year=Y&month=M
    ///
    /// 為什麼有獨立端點 | Why a dedicated endpoint:
    /// /transactions/ 是「跨帳戶共用交易」的彙整視圖，可能因伺服器邏輯（過濾、
    /// 權限、快取）導致客戶端再二次篩選時與真實帳戶資料不同步。每個帳戶有自己
    /// 的權威端點，回傳該帳戶完整且最新的交易，避免 client 自己用算的出錯。
    /// /transactions/ is an aggregated view across accounts and may drift from a
    /// given account's authoritative data once we filter client-side. Each
    /// account has its own endpoint that returns the full, fresh per-account
    /// data — preferred whenever we need a specific account's summary.
    func getAccountTransactions(accountId: String,
                                month: String? = nil,
                                fullURL: String? = nil) async throws -> PaginatedTransactionList {
        let data: Data
        if let url = fullURL {
            data = try await client.requestData(url: url)
        } else {
            let year: Int
            let monthNum: Int
            if let m = month, m.contains("-") {
                let parts = m.split(separator: "-")
                year     = Int(parts[0]) ?? Calendar.current.component(.year,  from: Date())
                monthNum = Int(parts[1]) ?? Calendar.current.component(.month, from: Date())
            } else {
                year     = Calendar.current.component(.year,  from: Date())
                monthNum = Calendar.current.component(.month, from: Date())
            }
            data = try await client.requestData(
                path: "/accounts/\(accountId)/transactions/?year=\(year)&month=\(monthNum)"
            )
        }
        return try decodeTransactionList(from: data)
    }

    /// 获取单个交易 | Get single transaction
    /// 按ID查询单个交易的详细信息
    /// Query detailed info of single transaction by ID
    ///
    /// HTTP GET /transactions/{id}/
    ///
    /// 路径参数 | Path parameter:
    /// {id} - 交易ID，从列表响应中获得 | transaction ID, obtained from list response
    func getTransaction(id: String) async throws -> Transaction {
        // 字符串插值 | String interpolation
        // \(id) 将id变量嵌入到路径字符串中
        // \(id) embeds id variable into path string
        // 例如，如果id="abc123"，路径变为 "/transactions/abc123/"
        // E.g., if id="abc123", path becomes "/transactions/abc123/"
        return try await client.request(path: "/transactions/\(id)/")
    }

    /// 创建新交易 | Create new transaction
    ///
    /// HTTP 方法 | HTTP method: POST /transactions/
    ///
    /// 请求体格式 | Request body format:
    /// CreateTransactionRequest 对象包含：
    /// CreateTransactionRequest object contains:
    /// - amount: 金额 | amount
    /// - category: 类别 | category
    /// - date: 日期 | date
    /// - description: 描述 | description
    /// - account: 共享账户（可选）| shared account (optional)
    ///
    /// 成功响应 (201 Created) 返回创建的交易对象，包含新生成的ID
    /// Success response (201 Created) returns created transaction object with new ID
    func createTransaction(_ req: CreateTransactionRequest) async throws -> Transaction {
        // 编码请求对象为JSON | Encode request object as JSON
        // CreateTransactionRequest 遵循 Encodable 协议
        // CreateTransactionRequest conforms to Encodable protocol
        // encoder 会自动将对象字段映射到JSON字段名
        // encoder automatically maps object fields to JSON field names
        let body = try client.encoder.encode(req)
        // 泛型推断 <Transaction> 期望响应为Transaction对象
        // Generic inference <Transaction> expects response as Transaction object
        return try await client.request(path: "/transactions/", method: "POST", body: body)
    }

    /// 更新交易 | Update transaction
    /// 部分更新（PATCH）vs 完全替换（PUT）
    /// Partial update (PATCH) vs complete replacement (PUT)
    ///
    /// HTTP 方法 | HTTP method: PATCH /transactions/{id}/
    ///
    /// PATCH 语义 | PATCH semantics:
    /// - 只更新提供的字段 | Only update provided fields
    /// - 未提供的字段保持不变 | Unmodified fields remain unchanged
    /// - 例如，只修改金额而保持日期和类别不变 | E.g., change amount, keep date and category
    ///
    /// 这与PUT不同：
    /// Different from PUT:
    /// - PUT 需要提供完整对象，未提供的字段变为null/默认值
    /// - PUT requires complete object, unspecified fields become null/default
    /// - PATCH 更灵活，只需指定要修改的字段
    /// - PATCH more flexible, only need to specify fields to change
    func updateTransaction(id: String, req: CreateTransactionRequest) async throws -> Transaction {
        let body = try client.encoder.encode(req)
        // PATCH 方法用于部分更新 | PATCH method for partial update
        return try await client.request(path: "/transactions/\(id)/", method: "PATCH", body: body)
    }

    /// 删除交易 | Delete transaction
    ///
    /// HTTP 方法 | HTTP method: DELETE /transactions/{id}/
    ///
    /// 删除语义 | Delete semantics:
    /// - 服务器会删除ID为 {id} 的交易记录 | Server deletes transaction with ID {id}
    /// - 通常返回204 No Content或200 OK | Usually returns 204 No Content or 200 OK
    /// - 不返回响应体 | No response body
    ///
    /// 错误处理 | Error handling:
    /// - 如果交易不存在，服务器返回404 | If transaction doesn't exist, server returns 404
    /// - 如果用户无权限删除，返回403 | If user lacks permission, returns 403
    func deleteTransaction(id: String) async throws {
        // requestVoid 用于不需要解析响应的请求
        // requestVoid used for requests that don't need response parsing
        try await client.requestVoid(path: "/transactions/\(id)/", method: "DELETE")
    }

    /// 获取个人交易 | Fetch personal transactions
    /// 仅获取当前用户作为付款人的交易（不含共享账户交易）
    /// Fetch only transactions where current user is payer (excludes shared account transactions)
    ///
    /// 个人交易 vs 共享账户交易 | Personal vs Shared account transactions:
    /// - 个人交易：只有当前用户可见 | Personal: visible only to current user
    /// - 共享账户交易：多个用户可见 | Shared: visible to multiple users
    ///
    /// 响应格式兼容性 | Response format compatibility:
    /// 后端API的 /transactions/mine/ 可能返回3种格式：
    /// Backend API's /transactions/mine/ might return 3 formats:
    /// 1. 分页格式 (与 /transactions/ 相同) | Paginated format (same as /transactions/)
    /// 2. 纯数组 [{ transaction1 }, { transaction2 }] | Plain array
    /// 3. 单个对象 { transaction } | Single object
    ///
    /// 这可能是API设计的不一致，所以我们需要尝试多种解码策略
    /// This might be API design inconsistency, so we try multiple decode strategies
    func getMyTransactions(fullURL: String? = nil, month: String? = nil) async throws -> PaginatedTransactionList {
        // Parse year/month — accepts "yyyy-MM" string or falls back to today
        let year: Int
        let monthNum: Int
        if let month = month, month.contains("-") {
            let parts = month.split(separator: "-")
            year     = Int(parts[0]) ?? Calendar.current.component(.year,  from: Date())
            monthNum = Int(parts[1]) ?? Calendar.current.component(.month, from: Date())
        } else {
            year     = Calendar.current.component(.year,  from: Date())
            monthNum = Calendar.current.component(.month, from: Date())
        }
        let path = "/transactions/mine/?year=\(year)&month=\(monthNum)"

        let data: Data = fullURL != nil
            ? try await client.requestData(url: fullURL!)
            : try await client.requestData(path: path)

        return try decodeTransactionList(from: data)
    }

    private func decodeTransactionList(from data: Data) throws -> PaginatedTransactionList {
        let decoder = client.decoder

        if let paginated = try? decoder.decode(PaginatedTransactionList.self, from: data),
           paginated.count != nil || !paginated.results.isEmpty {
            return paginated
        }

        if let list = try? decoder.decode([Transaction].self, from: data) {
            return PaginatedTransactionList(
                currentMonth: nil,
                previousMonthUrl: nil,
                nextMonthUrl: nil,
                count: list.count,
                results: list
            )
        }

        if let single = try? decoder.decode(Transaction.self, from: data) {
            return PaginatedTransactionList(
                currentMonth: nil,
                previousMonthUrl: nil,
                nextMonthUrl: nil,
                count: 1,
                results: [single]
            )
        }

        do {
            return try decoder.decode(PaginatedTransactionList.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - AI Parse
    // AI 解析 | AI Parsing
    // 使用大语言模型(LLM)解析自由格式文本为结构化交易数据
    // Use Large Language Model (LLM) to parse free-form text into structured transaction data

    /// 发送文本到LLM解析器，返回解析的交易列表
    /// Send free-form text to LLM parser, returns parsed transactions
    ///
    /// AI 解析流程 | AI parsing flow:
    /// 1. 用户输入自由格式文本（如"咖啡 5块钱"）| User enters free-form text (e.g., "coffee $5")
    /// 2. 发送到后端的 LLM 解析器（通常是 OpenAI API）| Send to backend LLM parser (usually OpenAI)
    /// 3. LLM 理解上下文，解析出结构化交易 | LLM understands context, extracts structured transaction
    /// 4. 返回解析的交易列表（可能包含多个交易）| Return list of parsed transactions (might contain multiple)
    /// 5. 前端显示解析结果供用户确认 | Frontend shows parsed results for user confirmation
    ///
    /// source 参数 | source parameter:
    /// - "voice" - 文本来自语音识别(STT) | Text from speech-to-text (STT)
    /// - "receipt" - 文本来自收据OCR | Text from receipt OCR
    /// - nil - 不知道来源 | Unknown source
    ///
    /// 服务器使用 source 信息定制 LLM 提示词（prompt），
    /// Server uses source info to customize LLM prompt,
    /// 例如，语音识别的文本更可能包含口语表达（"五块钱" 而非 "¥5"）
    /// e.g., speech text more likely contains colloquialisms ("five bucks" vs "¥5")
    func parseText(_ text: String, source: ParseSource? = nil) async throws -> [Transaction] {
        let req  = TransactionParseRequest(text: text, source: source)
        let body = try client.encoder.encode(req)
        // 返回 [Transaction] 数组，因为单个文本可能解析为多个交易
        // Returns [Transaction] array, because single text might parse to multiple transactions
        // 例如："买咖啡5块、饼干3块" 可能解析为两个交易
        // E.g., "bought coffee $5, biscuit $3" might parse to two transactions
        do {
            return try await client.request(path: "/transaction-parsers/parse/", method: "POST", body: body)
        } catch {
            // [DEBUG] 印出完整 decode error，找到確切的失敗欄位和型別
            // [DEBUG] Print full decode error to identify exact failing field and type
            if case APIError.decodingError(let decodeError) = error {
                print("[parseText] DECODE ERROR DETAIL: \(decodeError)")
                if let decodingErr = decodeError as? DecodingError {
                    switch decodingErr {
                    case .keyNotFound(let key, let ctx):
                        print("[parseText] keyNotFound: key='\(key.stringValue)' path=\(ctx.codingPath.map(\.stringValue))")
                    case .typeMismatch(let type, let ctx):
                        print("[parseText] typeMismatch: expected=\(type) path=\(ctx.codingPath.map(\.stringValue))")
                    case .valueNotFound(let type, let ctx):
                        print("[parseText] valueNotFound: type=\(type) path=\(ctx.codingPath.map(\.stringValue))")
                    case .dataCorrupted(let ctx):
                        print("[parseText] dataCorrupted: \(ctx.debugDescription) path=\(ctx.codingPath.map(\.stringValue))")
                    @unknown default:
                        print("[parseText] unknown decode error")
                    }
                }
            }
            throw error
        }
    }

    // MARK: - Upload (for future server-side Whisper / OCR)
    // 上传（用于未来的服务器端语音/OCR） | Upload (for future server-side Whisper/OCR)
    // 以下是占位符，服务器实现后将启用
    // Following are placeholders, will enable when server implements them

    /// 上传音频文件进行服务器端转录 | Upload audio file for server-side transcription
    /// 占位符 - 当后端Whisper准备好时，调用此方法替代客户端STT
    /// Placeholder - call this instead of client-side STT when backend Whisper is ready
    ///
    /// 为什么需要服务器端转录？| Why server-side transcription?
    /// 客户端STT (Speech-to-Text) 优势：
    /// Client STT advantages:
    /// - 无需上传音频，隐私更好 | No upload needed, better privacy
    /// - 离线工作 | Works offline
    ///
    /// 服务器端STT 优势：
    /// Server-side STT advantages:
    /// - 更精准的模型（OpenAI Whisper） | More accurate model (OpenAI Whisper)
    /// - 支持多种语言 | Supports multiple languages
    /// - 自动纠正错误 | Auto-correct errors
    ///
    /// 使用 Whisper API 的流程：
    /// Whisper API flow:
    /// 1. 前端上传 m4a/mp3 音频文件 | Frontend uploads m4a/mp3 audio file
    /// 2. 后端调用 OpenAI Whisper API | Backend calls OpenAI Whisper API
    /// 3. Whisper 返回转录文本 | Whisper returns transcribed text
    /// 4. 后端返回转录文本给前端 | Backend returns text to frontend
    func uploadAudio(data: Data, fileName: String = "recording.m4a") async throws {
        // Placeholder: when backend Whisper is ready, call this instead of client-side STT
        // let _: AudioUploadResponse = try await client.uploadMultipart(
        //     path: "/transaction-parsers/upload/audio/",
        //     fileData: data, fileName: fileName, mimeType: "audio/m4a", fieldName: "file"
        // )
    }

    /// 上传收据图片进行服务器端OCR | Upload receipt image for server-side OCR
    /// 占位符 - 当后端OCR准备好时，调用此方法替代客户端Vision
    /// Placeholder - call this instead of client-side Vision when backend OCR is ready
    ///
    /// 为什么需要服务器端OCR？| Why server-side OCR?
    /// 客户端Vision (Apple Vision framework) 优势：
    /// Client Vision advantages:
    /// - 离线工作 | Works offline
    /// - 不上传图片，隐私更好 | No upload, better privacy
    ///
    /// 服务器端OCR 优势：
    /// Server-side OCR advantages:
    /// - 使用更强大的模型（Google Tesseract、Claude Vision等）| More powerful models
    /// - 更准确的金融数据识别 | More accurate financial data recognition
    /// - 可与 LLM 整合，直接生成交易 | Can integrate with LLM to directly generate transactions
    ///
    /// 使用服务器OCR的流程：
    /// Server OCR flow:
    /// 1. 前端上传收据JPG/PNG图片 | Frontend uploads receipt JPG/PNG image
    /// 2. 后端使用 Tesseract/Claude Vision 提取文本 | Backend uses Tesseract/Claude Vision to extract text
    /// 3. 使用 LLM 解析提取的文本为交易 | Use LLM to parse extracted text into transactions
    /// 4. 返回解析的交易给前端 | Return parsed transactions to frontend
    func uploadReceipt(data: Data, fileName: String = "receipt.jpg") async throws {
        // Placeholder: when backend OCR is ready, call this instead of client-side Vision
        // let _: ReceiptUploadResponse = try await client.uploadMultipart(
        //     path: "/transaction-parsers/upload/receipt/",
        //     fileData: data, fileName: fileName, mimeType: "image/jpeg", fieldName: "image"
        // )
    }
}
