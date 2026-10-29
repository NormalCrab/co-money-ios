import Foundation
import Testing
@testable import MMCore

/// 依規格組出來的發票 QR（不是真的發票）。拿到真的發票後要補實際的例子。
private let fixed =
    "AB12345678" + "1151027" + "5678" + "000004C3" + "00000500" + "00000000" + "24546138"
    + "ABCDEFGHIJKLMNOPQRSTUVWX"

@Suite("電子發票 QR")
struct InvoiceQRTests {
    @Test("讀出字軌、民國年日期、16 進位的總金額")
    func fixedFields() throws {
        let invoice = try #require(InvoiceQR.parse(left: fixed + ":**********:2:3:1:鮮奶:2:95:高麗菜:1:60"))

        #expect(invoice.number == "AB12345678")
        #expect(invoice.date == LocalDate(year: 2026, month: 10, day: 27))
        #expect(invoice.total == 1280)
        #expect(invoice.sellerId == "24546138")
        #expect(invoice.items.map(\.name) == ["鮮奶", "高麗菜"])
        #expect(invoice.items[0].quantity == 2)
        #expect(invoice.items[0].unitPrice == 95)
    }

    @Test("右邊 QR 接著寫放不下的品項")
    func rightCode() throws {
        let invoice = try #require(InvoiceQR.parse(
            left: fixed + ":**********:2:3:1:鮮奶:2:95:高麗菜:1:60", right: "**雞腿肉:3:179"))

        #expect(invoice.items.map(\.name) == ["鮮奶", "高麗菜", "雞腿肉"])
    }

    @Test("Base64 的品名")
    func base64Names() throws {
        let name = Data("鮮奶".utf8).base64EncodedString()
        let invoice = try #require(InvoiceQR.parse(left: fixed + ":**********:1:1:2:\(name):2:95"))

        #expect(invoice.items.first?.name == "鮮奶")
    }

    @Test("附在 OCR 後面的說明：總計以 QR 為準；放不下的品項註明總數")
    func summary() throws {
        let invoice = try #require(InvoiceQR.parse(left: fixed + ":**********:2:9:1:鮮奶:2:95:高麗菜:1:60"))

        #expect(invoice.summary == """
        電子發票 QR：AB12345678，2026-10-27，總計 1280 元
        品項：鮮奶 2 x 95；高麗菜 1 x 60；…（共 9 項）
        """)
    }

    @Test("只有固定欄位、沒有品項也可以")
    func withoutItems() throws {
        let invoice = try #require(InvoiceQR.parse(left: fixed))
        #expect(invoice.items.isEmpty)
        #expect(invoice.summary == "電子發票 QR：AB12345678，2026-10-27，總計 1280 元")
    }

    @Test("不是發票的 QR（網址、太短、日期不對）回傳 nil")
    func notAnInvoice() {
        #expect(InvoiceQR.parse(left: "https://example.com/some/very/long/path/that/is/longer/than/seventy/seven/chars") == nil)
        #expect(InvoiceQR.parse(left: "AB12345678") == nil)
        #expect(InvoiceQR.parse(left: "AB12345678" + "1151327" + String(fixed.dropFirst(17))) == nil)
    }
}

@Suite("收據文字")
struct ReceiptTextTests {
    @Test("同一列的品名和金額接在一起，由上而下")
    func assemblesRows() {
        let lines = [
            RecognizedLine(text: "190", minX: 0.8, minY: 0.30, height: 0.03),
            RecognizedLine(text: "鮮奶 2 x 95", minX: 0.1, minY: 0.305, height: 0.03),
            RecognizedLine(text: "全聯福利中心", minX: 0.3, minY: 0.05, height: 0.04),
            RecognizedLine(text: "高麗菜 1 x 60", minX: 0.1, minY: 0.35, height: 0.03),
            RecognizedLine(text: "60", minX: 0.8, minY: 0.348, height: 0.03),
        ]

        #expect(ReceiptText.assemble(lines) == "全聯福利中心\n鮮奶 2 x 95 190\n高麗菜 1 x 60 60")
    }

    @Test("字太少或沒有數字：提示重拍")
    func tooLittle() {
        #expect(ReceiptText.isTooLittle("全聯"))
        #expect(ReceiptText.isTooLittle("謝謝光臨歡迎再來"))
        #expect(!ReceiptText.isTooLittle("鮮奶 2 x 95"))
    }

    @Test("有發票 QR 時附在後面")
    func compose() throws {
        let invoice = try #require(InvoiceQR.parse(left: fixed))
        #expect(ReceiptText.compose(ocr: "總計 1,28O\n", invoice: invoice)
            == "總計 1,28O\n---\n電子發票 QR：AB12345678，2026-10-27，總計 1280 元")
        #expect(ReceiptText.compose(ocr: " 總計 1280 ", invoice: nil) == "總計 1280")
    }
}

@Suite("等待解析結果")
struct ParseJobWaiterTests {
    final class Counter: @unchecked Sendable {
        let lock = NSLock()
        var value = 0
        func next() -> Int { lock.withLock { value += 1; return value } }
    }

    func job(_ status: ParseJobStatus) throws -> ParseJob {
        try APICoding.decoder().decode(ParseJob.self, from: Data(parseJobJSON(id: UUID(), status: status.rawValue).utf8))
    }

    @Test("好了就回傳")
    func returnsWhenDone() async throws {
        let counter = Counter()
        let running = try job(.running), done = try job(.done)

        let result = try await ParseJobWaiter.wait(
            for: UUID(), fetch: { _ in counter.next() < 3 ? running : done }, sleep: { _ in })

        #expect(result?.status == .done)
        #expect(counter.value == 3)
    }

    @Test("30 秒內沒好就不等了（每 2 秒查一次，共 15 次）")
    func givesUp() async throws {
        let counter = Counter()
        let running = try job(.running)

        let result = try await ParseJobWaiter.wait(
            for: UUID(), fetch: { _ in _ = counter.next(); return running }, sleep: { _ in })

        #expect(result == nil)
        #expect(counter.value == 15)
    }
}
