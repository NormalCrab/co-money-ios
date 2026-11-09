import Foundation

/// tag 的顏色：App 依 tag 自動配色，不存在後端（Alex 2026-11-09）。
///
/// 只回傳色盤的第幾格，實際的顏色由 App 決定。同一份 tag 清單在每支手機上算出來的結果都一樣，
/// 所以全家人看到的顏色相同。
public enum TagColors {
    /// 這個 tag 最想要的格子：用 UUID 的位元組算（不能用 `hashValue`，它每次開 app 都不一樣）。
    public static func preferredSlot(for key: UUID, count: Int) -> Int {
        precondition(count > 0)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a
        withUnsafeBytes(of: key.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01b3
            }
        }
        return Int(hash % UInt64(count))
    }

    /// 幫一組 tag 分配格子，盡量不重複。
    ///
    /// 先讓每個 tag 拿最想要的格子（撞到時 UUID 排前面的拿），沒拿到的再往後找空的。
    /// 這樣新增一個 tag 時，只要它想要的格子是空的，其他 tag 的顏色都不會變。
    /// tag 比格子多時，多出來的只好和別人共用最想要的格子。
    public static func assign(_ keys: [UUID], count: Int) -> [UUID: Int] {
        let ordered = Array(Set(keys)).sorted { $0.uuidString < $1.uuidString }
        var result: [UUID: Int] = [:]
        var taken = Set<Int>()
        for key in ordered {
            let slot = preferredSlot(for: key, count: count)
            if taken.insert(slot).inserted { result[key] = slot }
        }
        for key in ordered where result[key] == nil {
            let preferred = preferredSlot(for: key, count: count)
            let free = (0..<count).map { (preferred + $0) % count }.first { !taken.contains($0) }
            if let free { taken.insert(free) }
            result[key] = free ?? preferred
        }
        return result
    }
}

extension Tag {
    /// 決定顏色用的 key：週期 tag 用規則（每一期都是同一個顏色），一次性 tag 用自己。
    public var colorKey: UUID { rule ?? id }
}

extension TagLite {
    /// 同 `Tag.colorKey`。
    public var colorKey: UUID { rule ?? id }
}
