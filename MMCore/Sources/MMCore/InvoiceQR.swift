import Foundation

/// 台灣電子發票證明聯上的 QR code（ios-design §1.2）。
///
/// 依財政部「電子發票證明聯一維及二維條碼規格說明」：
///
/// 左邊的 QR，前 77 個字是固定欄位：
///
/// | 位置 | 長度 | 內容 |
/// |---|---|---|
/// | 0 | 10 | 發票字軌號碼（AB12345678） |
/// | 10 | 7 | 開立日期，民國年 yyyMMdd（1151027） |
/// | 17 | 4 | 隨機碼 |
/// | 21 | 8 | 銷售額（未稅），16 進位 |
/// | 29 | 8 | 總計額（含稅），16 進位 |
/// | 37 | 8 | 買方統一編號（沒有是 00000000） |
/// | 45 | 8 | 賣方統一編號 |
/// | 53 | 24 | 加密驗證資訊 |
///
/// 之後用冒號分隔：營業人自行使用區（10 字）、這個 QR 記了幾個品項、發票總共幾個品項、
/// 中文編碼（0 Big5、1 UTF-8、2 Base64），再來是「品名:數量:單價」一直重複。
/// 右邊的 QR 以 `**` 開頭，接著寫左邊放不下的品項。
///
/// - Note: 實作時沒有規格書原文可以對照，Base64 的部分（整段編碼還是每個品名各自編碼）
///   兩種都試。拿到真的發票後要用實際的 QR 補測試。Big5 編碼的品名在 iOS 上
///   `payloadStringValue` 可能已經是亂碼，那時只用金額和日期。
public struct InvoiceQR: Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        public var name: String
        public var quantity: Decimal
        public var unitPrice: Decimal
    }

    public var number: String
    public var date: LocalDate
    public var randomCode: String
    /// 含稅的總金額。比 OCR 準（OCR 常把 8 認成 B、0 認成 O），送給 LLM 時註明以它為準。
    public var total: Int
    public var sellerId: String
    public var items: [Item]
    /// 發票上的品項總數（可能比 `items` 多：QR 放不下的品項不會出現）。
    public var itemCount: Int

    /// 解析左邊的 QR，右邊的有的話一起給。不是電子發票的 QR 回傳 nil。
    public static func parse(left: String, right: String? = nil) -> InvoiceQR? {
        let chars = Array(left)
        guard chars.count >= 77 else { return nil }
        func field(_ start: Int, _ length: Int) -> String { String(chars[start..<start + length]) }

        let number = field(0, 10)
        guard number.prefix(2).allSatisfy({ $0.isASCII && $0.isUppercase }),
              number.suffix(8).allSatisfy({ $0.isASCII && $0.isNumber }),
              let date = rocDate(field(10, 7)),
              let total = Int(field(29, 8), radix: 16)
        else { return nil }

        var invoice = InvoiceQR(number: number, date: date, randomCode: field(17, 4), total: total,
                                sellerId: field(45, 8), items: [], itemCount: 0)

        // 冒號後面的部分：["", 自行使用區, 記載筆數, 總筆數, 編碼, 品名, 數量, 單價, ...]
        let rest = String(chars[77...])
        let header = rest.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard header.count >= 5 else { return invoice }
        invoice.itemCount = Int(header[3]) ?? 0
        let encoding = header[4]

        var detail = header.count > 5 ? header[5] : ""
        if let right, right.hasPrefix("**") {
            let more = String(right.dropFirst(2))
            if !more.isEmpty { detail += (detail.isEmpty || detail.hasSuffix(":") ? "" : ":") + more }
        }
        invoice.items = items(in: detail, encoding: encoding)
        invoice.itemCount = max(invoice.itemCount, invoice.items.count)
        return invoice
    }

    /// 附在 OCR 文字後面的說明（§1.2 的格式）。
    public var summary: String {
        var lines = ["電子發票 QR：\(number)，\(date)，總計 \(total) 元"]
        if !items.isEmpty {
            var list = items.map { "\($0.name) \(plain($0.quantity)) x \(plain($0.unitPrice))" }
                .joined(separator: "；")
            if itemCount > items.count { list += "；…（共 \(itemCount) 項）" }
            lines.append("品項：" + list)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: -

    static func rocDate(_ text: String) -> LocalDate? {
        guard text.count == 7, let year = Int(text.prefix(3)),
              let month = Int(text.dropFirst(3).prefix(2)), let day = Int(text.suffix(2)),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return LocalDate(year: year + 1911, month: month, day: day)
    }

    static func items(in detail: String, encoding: String) -> [Item] {
        if encoding == "2" {
            // 整段 Base64：解得開而且裡面有冒號，就是整段編碼。
            if let data = Data(base64Encoded: detail), let decoded = String(data: data, encoding: .utf8),
               decoded.contains(":") {
                return triples(decoded, decodeNames: false)
            }
            return triples(detail, decodeNames: true)
        }
        return triples(detail, decodeNames: false)
    }

    private static func triples(_ detail: String, decodeNames: Bool) -> [Item] {
        let parts = detail.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var result: [Item] = []
        var index = 0
        while index + 2 < parts.count {
            var name = parts[index].trimmingCharacters(in: .whitespaces)
            if decodeNames, let data = Data(base64Encoded: name), let decoded = String(data: data, encoding: .utf8) {
                name = decoded
            }
            if let quantity = decimal(parts[index + 1]), let price = decimal(parts[index + 2]), !name.isEmpty {
                result.append(Item(name: name, quantity: quantity, unitPrice: price))
            }
            index += 3
        }
        return result
    }

    private static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func plain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
