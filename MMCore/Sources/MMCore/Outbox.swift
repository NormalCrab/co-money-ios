import Foundation

/// 要建立的解析工作。檔案先存在手機上，`audioFile` / `imageFile` 是附件資料夾裡的檔名。
public struct ParseJobUpload: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var ledgerId: UUID
    public var source: ParseSource
    public var text: String
    /// 使用者記錄的時間。後端用它換成帳本時區的「今天」，離線記的帳日期才不會錯（§2.1）。
    public var capturedAt: Date
    public var audioFile: String?
    public var imageFile: String?

    public init(id: UUID = UUID(), ledgerId: UUID, source: ParseSource, text: String,
                capturedAt: Date, audioFile: String? = nil, imageFile: String? = nil) {
        self.id = id
        self.ledgerId = ledgerId
        self.source = source
        self.text = text
        self.capturedAt = capturedAt
        self.audioFile = audioFile
        self.imageFile = imageFile
    }
}

/// 一個要送給後端的寫入。每一種都可以安全重送（ios-design §3.1）。
public enum OutboxOperation: Codable, Hashable, Sendable {
    case createTransaction(TransactionInput)
    case createParseJob(ParseJobUpload)
    case confirmParseJob(jobId: UUID, transactions: [TransactionInput])
    case discardParseJob(jobId: UUID)

    /// 附件的檔名（送出成功或捨棄後要刪掉）。
    public var attachments: [String] {
        if case .createParseJob(let upload) = self {
            return [upload.audioFile, upload.imageFile].compactMap { $0 }
        }
        return []
    }

    /// 待上傳清單上的標題。
    public var title: String {
        switch self {
        case .createTransaction(let input):
            let amount = input.displayAmount.map { "\($0.1.map { $0 + " " } ?? "")\($0.0.display)" } ?? ""
            return [input.description, amount].filter { !$0.isEmpty }.joined(separator: " ")
        case .createParseJob(let upload):
            switch upload.source {
            case .receipt: return "收據"
            case .voice, .manual: return "「\(upload.text.prefix(20))」"
            }
        case .confirmParseJob(_, let transactions):
            return "加入 \(transactions.count) 筆"
        case .discardParseJob:
            return "捨棄解析結果"
        }
    }
}

public enum OutboxState: Codable, Hashable, Sendable {
    /// 等著送出（可能是第一次，也可能是在等下一次重試）。
    case waiting
    /// 後端拒絕了這筆資料（4xx），重送也沒用，要使用者修改或捨棄。
    case needsAttention(String)
}

public struct OutboxItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// 建立這筆的使用者。只有同一個人登入時才會送出（§3.3）。
    public var userId: Int
    public var operation: OutboxOperation
    public var createdAt: Date
    public var state: OutboxState
    public var attempts: Int
    /// 下次可以送出的時間。重試的間隔越拉越長（§4.3）。
    public var nextAttemptAt: Date
    /// 最後一次失敗的原因（重試中的也會記，給「待上傳」清單顯示）。
    public var lastError: String?

    public var needsAttention: Bool {
        if case .needsAttention = state { return true }
        return false
    }
}

/// 把待上傳的項目實際送出去。app 用 `APIOutboxSender`，測試用假的。
public protocol OutboxSender: Sendable {
    func send(_ operation: OutboxOperation) async throws
}

/// 存待上傳清單的地方。每次變動都整份寫回去：清單很短（通常是個位數），簡單比較不會出錯。
public protocol OutboxStore: Sendable {
    func load() -> [OutboxItem]
    func save(_ items: [OutboxItem])
}

/// 存成 app 資料夾裡的一個 JSON 檔。
public struct FileOutboxStore: OutboxStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> [OutboxItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? APICoding.decoder().decode([OutboxItem].self, from: data)) ?? []
    }

    public func save(_ items: [OutboxItem]) {
        guard let data = try? APICoding.encoder().encode(items) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// 一次送出的結果，給畫面和測試看。
public struct DrainReport: Hashable, Sendable {
    public var sent: [UUID] = []
    public var retrying: [UUID] = []
    public var needsAttention: [UUID] = []
    /// 送到一半發現登入失效：剩下的都沒送，等重新登入。
    public var stoppedForLogin = false
}

/// 待上傳佇列（ios-design §4.3）。
///
/// ```
/// 等待 ──送出──▶ 成功 → 移除
///   ▲             │
///   └─稍後重試◀───┤ 沒網路、5xx：5 秒、30 秒、2 分鐘、10 分鐘、之後每 30 分鐘
///                 └─需要處理 ◀── 4xx：資料本身有問題
/// ```
///
/// 每一筆互相獨立，一筆卡住不影響其他的。
public actor Outbox {
    /// 第 n 次失敗後要等幾秒才重試。
    public static let backoff: [TimeInterval] = [5, 30, 120, 600, 1800]

    private let store: OutboxStore
    private let sender: OutboxSender
    private let attachments: URL?
    private var draining = false
    public private(set) var items: [OutboxItem]

    /// - Parameter attachments: 附件資料夾。送出成功或捨棄時刪掉對應的檔案；nil 時不刪。
    public init(store: OutboxStore, sender: OutboxSender, attachments: URL? = nil) {
        self.store = store
        self.sender = sender
        self.attachments = attachments
        self.items = store.load()
    }

    public func items(for userId: Int) -> [OutboxItem] {
        items.filter { $0.userId == userId }
    }

    /// 某個帳本還沒上傳的交易（交易列表上標「等待上傳」，首頁註明「不含 N 筆」）。
    public func pendingTransactions(userId: Int, ledger: UUID) -> [TransactionInput] {
        items(for: userId).compactMap {
            if case .createTransaction(let input) = $0.operation, input.ledgerId == ledger { return input }
            return nil
        }
    }

    @discardableResult
    public func enqueue(_ operation: OutboxOperation, userId: Int, now: Date = Date()) -> OutboxItem {
        let item = OutboxItem(id: UUID(), userId: userId, operation: operation, createdAt: now,
                              state: .waiting, attempts: 0, nextAttemptAt: now, lastError: nil)
        items.append(item)
        store.save(items)
        return item
    }

    /// 使用者修改了「需要處理」的項目：換成新的內容，重新開始計算重試。
    public func replace(_ id: UUID, with operation: OutboxOperation, now: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].operation = operation
        items[index].state = .waiting
        items[index].attempts = 0
        items[index].nextAttemptAt = now
        items[index].lastError = nil
        store.save(items)
    }

    /// 使用者捨棄這一筆。
    public func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        deleteAttachments(of: items[index].operation)
        items.remove(at: index)
        store.save(items)
    }

    /// 網路恢復、回到前景時，讓所有等待中的立刻重試。
    public func retryNow(now: Date = Date()) {
        for index in items.indices where !items[index].needsAttention {
            items[index].nextAttemptAt = now
        }
        store.save(items)
    }

    /// 下一筆可以送出的時間（排下一次送出用）。沒有等待中的項目時是 nil。
    public func nextAttemptDate(userId: Int) -> Date? {
        items(for: userId).filter { !$0.needsAttention }.map(\.nextAttemptAt).min()
    }

    /// 依建立順序送出這個使用者所有到期的項目。
    ///
    /// 同時只會有一輪在跑；重複呼叫（網路恢復和回到前景同時發生）時，後到的直接返回。
    public func drain(userId: Int, now: Date = Date()) async -> DrainReport {
        var report = DrainReport()
        guard !draining else { return report }
        draining = true
        defer { draining = false }

        let due = items
            .filter { $0.userId == userId && !$0.needsAttention && $0.nextAttemptAt <= now }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.id)

        sending: for id in due {
            guard let item = items.first(where: { $0.id == id }) else { continue }  // 送的期間被捨棄了
            do {
                try await sender.send(item.operation)
                deleteAttachments(of: item.operation)
                items.removeAll { $0.id == id }
                report.sent.append(id)
            } catch let error as APIError where error == .unauthorized {
                report.stoppedForLogin = true
                break sending
            } catch {
                let failure = Self.classify(error, for: item.operation)
                update(id) { item in
                    item.attempts += 1
                    item.lastError = failure.message
                    switch failure {
                    case .done:
                        break
                    case .retry:
                        let delay = Self.backoff[min(item.attempts, Self.backoff.count) - 1]
                        item.nextAttemptAt = now.addingTimeInterval(delay)
                    case .needsAttention(let message):
                        item.state = .needsAttention(message)
                    }
                }
                switch failure {
                case .done:
                    deleteAttachments(of: item.operation)
                    items.removeAll { $0.id == id }
                    report.sent.append(id)
                case .retry: report.retrying.append(id)
                case .needsAttention: report.needsAttention.append(id)
                }
            }
            store.save(items)
        }
        return report
    }

    enum Failure: Equatable {
        /// 其實已經達到目的（例如要捨棄的工作已經不在了）。
        case done
        case retry(String)
        case needsAttention(String)

        var message: String {
            switch self {
            case .done: ""
            case .retry(let message), .needsAttention(let message): message
            }
        }
    }

    static func classify(_ error: Error, for operation: OutboxOperation) -> Failure {
        guard let error = error as? APIError else {
            return .retry(String(describing: error))
        }
        switch (error, operation) {
        case (.client(let status, _, _), .discardParseJob) where status == 404 || status == 409:
            // 工作已經被刪掉，或已經確認過了：捨棄這件事不用再做。
            return .done
        case (.client(409, _, _), .createTransaction), (.client(409, _, _), .createParseJob):
            return .needsAttention("這筆資料的編號和別人的重複，請捨棄後重新記一次")
        case (.client(_, let message, _), _):
            return .needsAttention(message)
        case (.decoding, _):
            // 後端已經收下了（2xx），只是回應讀不懂。送出這件事算成功。
            return .done
        default:
            return error.isRetryable ? .retry(error.message) : .needsAttention(error.message)
        }
    }

    private func update(_ id: UUID, _ change: (inout OutboxItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func deleteAttachments(of operation: OutboxOperation) {
        guard let attachments else { return }
        for name in operation.attachments {
            try? FileManager.default.removeItem(at: attachments.appendingPathComponent(name))
        }
    }
}

/// 用 API 送出待上傳的項目。附件從附件資料夾讀。
public struct APIOutboxSender: OutboxSender {
    public let client: APIClient
    public let attachments: URL

    public init(client: APIClient, attachments: URL) {
        self.client = client
        self.attachments = attachments
    }

    public func send(_ operation: OutboxOperation) async throws {
        switch operation {
        case .createTransaction(let input):
            _ = try await client.createTransaction(input)
        case .createParseJob(let upload):
            let audio = try upload.audioFile.map(read)
            let image = try upload.imageFile.map(read)
            _ = try await client.createParseJob(upload, audio: audio, image: image)
        case .confirmParseJob(let jobId, let transactions):
            _ = try await client.confirmParseJob(jobId, transactions: transactions)
        case .discardParseJob(let jobId):
            try await client.discardParseJob(jobId)
        }
    }

    /// 附件檔不見了（例如使用者清掉了 app 資料）：重試也沒用，要使用者處理。
    private func read(_ name: String) throws -> Data {
        do {
            return try Data(contentsOf: attachments.appendingPathComponent(name))
        } catch {
            throw APIError.client(status: 0, message: "找不到錄音或照片檔，請捨棄後重新記一次", fieldErrors: [:])
        }
    }
}
