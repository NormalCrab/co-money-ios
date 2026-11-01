import Foundation
import Testing
@testable import MMCore

/// 依序回傳指定的結果；沒指定的一律成功。
final class ScriptedSender: OutboxSender, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Error?]
    private(set) var sent: [OutboxOperation] = []

    init(_ script: [Error?] = []) {
        self.script = script
    }

    func send(_ operation: OutboxOperation) async throws {
        let next: Error? = lock.withLock {
            sent.append(operation)
            return script.isEmpty ? nil : script.removeFirst()
        }
        if let next { throw next }
    }
}

final class MemoryOutboxStore: OutboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [OutboxItem] = []
    func load() -> [OutboxItem] { lock.withLock { items } }
    func save(_ items: [OutboxItem]) { lock.withLock { self.items = items } }
}

@Suite("待上傳佇列")
struct OutboxTests {
    let now = Date(timeIntervalSince1970: 1_793_019_900)
    let alice = 7
    let bob = 8

    func expense(_ description: String = "午餐便當", amount: Money = 120) -> OutboxOperation {
        .createTransaction(TransactionInput(ledgerId: ledgerId, description: description, category: .food,
                                            transactionDate: now, amount: amount))
    }

    @Test("送出成功就移除")
    func success() async {
        let sender = ScriptedSender()
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        let item = await outbox.enqueue(expense(), userId: alice, now: now)

        let report = await outbox.drain(userId: alice, now: now)

        #expect(report.sent == [item.id])
        #expect(await outbox.items.isEmpty)
    }

    @Test("沒網路：留著，5 秒、30 秒、2 分鐘…越等越久，最長 30 分鐘")
    func backoff() async {
        let offline = APIError.offline("no network")
        let sender = ScriptedSender(Array(repeating: offline, count: 7))
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        await outbox.enqueue(expense(), userId: alice, now: now)

        var clock = now
        var waits: [TimeInterval] = []
        for _ in 0..<7 {
            _ = await outbox.drain(userId: alice, now: clock)
            let next = await outbox.items[0].nextAttemptAt
            waits.append(next.timeIntervalSince(clock))
            clock = next
        }

        #expect(waits == [5, 30, 120, 600, 1800, 1800, 1800])
        #expect(await outbox.items[0].lastError == offline.message)
    }

    @Test("還沒到重試時間的不送")
    func notDueYet() async {
        let sender = ScriptedSender([APIError.server(status: 503)])
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        await outbox.enqueue(expense(), userId: alice, now: now)
        _ = await outbox.drain(userId: alice, now: now)

        let report = await outbox.drain(userId: alice, now: now.addingTimeInterval(4))

        #expect(report == DrainReport())
        #expect(sender.sent.count == 1)
    }

    @Test("4xx：需要處理，不再自動重送；其他筆照樣送")
    func needsAttention() async {
        let rejected = APIError.client(status: 400, message: "家庭帳本還沒設定 JPY 匯率", fieldErrors: [:])
        let sender = ScriptedSender([rejected, nil])
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        let bad = await outbox.enqueue(expense("拉麵"), userId: alice, now: now)
        let good = await outbox.enqueue(expense("便當"), userId: alice, now: now.addingTimeInterval(1))

        let report = await outbox.drain(userId: alice, now: now.addingTimeInterval(2))
        let later = await outbox.drain(userId: alice, now: now.addingTimeInterval(9999))

        #expect(report.needsAttention == [bad.id])
        #expect(report.sent == [good.id])
        #expect(later == DrainReport())
        #expect(await outbox.items.map(\.state) == [.needsAttention("家庭帳本還沒設定 JPY 匯率")])
    }

    @Test("使用者改好之後重新開始")
    func replaceAfterFix() async {
        let rejected = APIError.client(status: 400, message: "請填金額", fieldErrors: [:])
        let sender = ScriptedSender([rejected])
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        let item = await outbox.enqueue(expense(), userId: alice, now: now)
        _ = await outbox.drain(userId: alice, now: now)

        let fixed = expense(amount: 150)
        await outbox.replace(item.id, with: fixed, now: now)
        let report = await outbox.drain(userId: alice, now: now)

        #expect(report.sent == [item.id])
        #expect(sender.sent.last == fixed)
    }

    @Test("登入失效：停下來，全部留著（不算失敗次數），重新登入後再送")
    func stopsForLogin() async {
        let sender = ScriptedSender([APIError.unauthorized])
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        await outbox.enqueue(expense("A"), userId: alice, now: now)
        await outbox.enqueue(expense("B"), userId: alice, now: now)

        let report = await outbox.drain(userId: alice, now: now)

        #expect(report.stoppedForLogin)
        #expect(sender.sent.count == 1)
        #expect(await outbox.items.map(\.attempts) == [0, 0])

        let again = await outbox.drain(userId: alice, now: now)
        #expect(again.sent.count == 2)
    }

    @Test("只送目前登入者的資料：換別人登入時不會送出")
    func boundToUser() async {
        let sender = ScriptedSender()
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        await outbox.enqueue(expense(), userId: alice, now: now)

        let report = await outbox.drain(userId: bob, now: now)

        #expect(report == DrainReport())
        #expect(sender.sent.isEmpty)
        #expect(await outbox.items(for: alice).count == 1)
    }

    @Test("要捨棄的解析工作已經不在了（404）或已經確認（409）：當作完成")
    func discardAlreadyGone() async {
        let sender = ScriptedSender([APIError.client(status: 404, message: "", fieldErrors: [:])])
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        await outbox.enqueue(.discardParseJob(jobId: UUID()), userId: alice, now: now)

        let report = await outbox.drain(userId: alice, now: now)

        #expect(report.sent.count == 1)
        #expect(await outbox.items.isEmpty)
    }

    @Test("送出成功後刪掉附件；還沒送的附件留著")
    func attachments() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("m4a".utf8).write(to: folder.appendingPathComponent("a.m4a"))
        try Data("jpg".utf8).write(to: folder.appendingPathComponent("b.jpg"))

        let sender = ScriptedSender([nil, APIError.offline("")])
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender, attachments: folder)
        func upload(_ audio: String?, _ image: String?) -> OutboxOperation {
            .createParseJob(ParseJobUpload(ledgerId: ledgerId, source: .voice, text: "x", capturedAt: now,
                                           audioFile: audio, imageFile: image))
        }
        await outbox.enqueue(upload("a.m4a", nil), userId: alice, now: now)
        await outbox.enqueue(upload(nil, "b.jpg"), userId: alice, now: now.addingTimeInterval(1))

        _ = await outbox.drain(userId: alice, now: now.addingTimeInterval(2))

        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.m4a").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("b.jpg").path))
    }

    @Test("附件檔不見了：需要處理，不會一直重試")
    func missingAttachment() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID())")
        let (client, transport, _) = makeClient { _ in json(202, "{}") }
        let outbox = Outbox(store: MemoryOutboxStore(), sender: APIOutboxSender(client: client, attachments: folder))
        await outbox.enqueue(.createParseJob(ParseJobUpload(
            ledgerId: ledgerId, source: .voice, text: "x", capturedAt: now, audioFile: "gone.m4a")),
            userId: alice, now: now)

        let report = await outbox.drain(userId: alice, now: now)

        #expect(report.needsAttention.count == 1)
        #expect(transport.requests.isEmpty)
    }

    @Test("清單存起來，app 重開後還在")
    func persists() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = Outbox(store: FileOutboxStore(url: url), sender: ScriptedSender())
        await first.enqueue(expense(), userId: alice, now: now)
        await first.enqueue(.confirmParseJob(jobId: UUID(), transactions: []), userId: alice, now: now)

        let reopened = Outbox(store: FileOutboxStore(url: url), sender: ScriptedSender())

        #expect(await reopened.items == first.items)
    }

    @Test("還沒上傳的交易依帳本列出")
    func pendingTransactions() async {
        let outbox = Outbox(store: MemoryOutboxStore(), sender: ScriptedSender())
        await outbox.enqueue(expense("A"), userId: alice, now: now)
        await outbox.enqueue(.discardParseJob(jobId: UUID()), userId: alice, now: now)
        await outbox.enqueue(.createTransaction(TransactionInput(
            ledgerId: UUID(), description: "別的帳本", category: .food, transactionDate: now, amount: 1)),
            userId: alice, now: now)

        let pending = await outbox.pendingTransactions(userId: alice, ledger: ledgerId)

        #expect(pending.map(\.description) == ["A"])
    }

    @Test("同時呼叫兩次 drain 不會重複送")
    func noDoubleDrain() async {
        let sender = ScriptedSender()
        let outbox = Outbox(store: MemoryOutboxStore(), sender: sender)
        await outbox.enqueue(expense(), userId: alice, now: now)

        async let a = outbox.drain(userId: alice, now: now)
        async let b = outbox.drain(userId: alice, now: now)
        _ = await (a, b)

        #expect(sender.sent.count == 1)
    }
}
