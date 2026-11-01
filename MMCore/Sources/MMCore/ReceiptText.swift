import Foundation

/// OCR 辨識出的一行字和它在圖片上的位置。
///
/// 座標是 0…1、**左上角為原點**。Vision 的 `boundingBox` 是左下角為原點，
/// app 轉過來時用 `minY = 1 - box.maxY`。
public struct RecognizedLine: Hashable, Sendable {
    public var text: String
    public var minX: Double
    public var minY: Double
    public var height: Double

    public init(text: String, minX: Double, minY: Double, height: Double) {
        self.text = text
        self.minX = minX
        self.minY = minY
        self.height = height
    }

    var midY: Double { minY + height / 2 }
}

/// 收據 OCR 文字的整理（ios-design §1.2）。
public enum ReceiptText {
    /// 依版面由上而下組成文字。同一列的片段（左邊品名、右邊金額）用空白接起來。
    ///
    /// Vision 會把同一列左右兩邊分成兩個結果，直接照順序接起來，品名和金額就對不上了。
    public static func assemble(_ lines: [RecognizedLine]) -> String {
        var rows: [[RecognizedLine]] = []
        for line in lines.sorted(by: { $0.midY < $1.midY }) {
            // 垂直中心落在上一列的範圍內就算同一列。
            if let last = rows.last?.first, abs(line.midY - last.midY) < max(last.height, line.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
            .map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// 辨識出的字太少：提示重拍或手動輸入，不浪費一次 LLM 呼叫（§1.2 第 3 點）。
    public static func isTooLittle(_ text: String) -> Bool {
        let meaningful = text.filter { !$0.isWhitespace }
        return meaningful.count < 6 || !meaningful.contains(where: \.isNumber)
    }

    /// 送給後端解析的文字：OCR 的結果，有發票 QR 的話附在後面。
    public static func compose(ocr: String, invoice: InvoiceQR?) -> String {
        let text = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let invoice else { return text }
        return text + "\n---\n" + invoice.summary
    }
}

/// 送出解析工作後，在畫面上等結果（§2.2）：每 2 秒查一次，最多 30 秒。
/// 等不到就算了，結果之後會出現在「待處理」。
public enum ParseJobWaiter {
    public static func wait(
        for id: UUID,
        interval: Duration = .seconds(2),
        timeout: Duration = .seconds(30),
        fetch: @Sendable (UUID) async throws -> ParseJob,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> ParseJob? {
        var waited = Duration.zero
        while waited < timeout {
            try await sleep(interval)
            waited += interval
            let job = try await fetch(id)
            if !job.status.isPending { return job }
        }
        return nil
    }
}

/// 畫面資料的快取（ios-design §4.2）：離線時顯示上次拿到的資料，標「資料更新於 10:42」。
///
/// 設計文件寫的是 SwiftData；這裡先用 JSON 檔，因為要在 Linux 上測試。資料量小
/// （帳本、tag、最近兩個月的交易），之後真的需要查詢再換。
public struct JSONCache: Sendable {
    public struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        public var value: Value
        public var updatedAt: Date
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func load<Value: Codable & Sendable>(_ type: Value.Type, key: String) -> Entry<Value>? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? APICoding.decoder().decode(Entry<Value>.self, from: data)
    }

    public func save<Value: Codable & Sendable>(_ value: Value, key: String, at date: Date = Date()) {
        guard let data = try? APICoding.encoder().encode(Entry(value: value, updatedAt: date)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
    }

    /// 登出時清掉，下一個登入的人看不到上一個人的資料。
    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }
}
