import Foundation
import Testing
@testable import MMCore

@Suite("tag 自動配色")
struct TagColorTests {
    let count = 10

    @Test("同一個 tag 每次算出來都一樣（全家人的手機顏色相同）")
    func preferredIsStable() throws {
        let key = try #require(UUID(uuidString: "0B6B6F2E-3D3A-4C6B-9C3E-2E1F7A5B8C9D"))
        let slot = TagColors.preferredSlot(for: key, count: count)
        #expect(TagColors.preferredSlot(for: key, count: count) == slot)
        #expect((0..<count).contains(slot))
    }

    @Test("tag 不比顏色多時，每個 tag 的顏色都不一樣")
    func distinctWhenEnoughColors() {
        for _ in 0..<50 {
            let keys = (0..<count).map { _ in UUID() }
            let slots = TagColors.assign(keys, count: count)
            #expect(Set(slots.values).count == count)
            #expect(slots.values.allSatisfy { (0..<count).contains($0) })
        }
    }

    @Test("清單的順序不影響結果")
    func orderDoesNotMatter() {
        let keys = (0..<6).map { _ in UUID() }
        #expect(TagColors.assign(keys, count: count) == TagColors.assign(keys.reversed(), count: count))
    }

    @Test("新增的 tag 想要的顏色沒人用時，其他 tag 的顏色不變")
    func addingKeepsOthers() {
        for _ in 0..<50 {
            let keys = (0..<4).map { _ in UUID() }
            let before = TagColors.assign(keys, count: count)
            let taken = Set(before.values)
            var newcomer = UUID()
            while taken.contains(TagColors.preferredSlot(for: newcomer, count: count)) { newcomer = UUID() }
            let after = TagColors.assign(keys + [newcomer], count: count)
            for key in keys { #expect(after[key] == before[key]) }
        }
    }

    @Test("tag 比顏色多時，每個 tag 還是有顏色")
    func moreKeysThanColors() {
        let keys = (0..<15).map { _ in UUID() }
        let slots = TagColors.assign(keys, count: count)
        #expect(slots.count == 15)
        #expect(Set(slots.values).count == count)
    }

    @Test("週期 tag 用規則決定顏色，每一期都一樣；一次性 tag 用自己")
    func colorKey() {
        let rule = UUID()
        let october = MMCore.Tag(id: UUID(), name: "伙食費 10 月", isPeriodic: true)
        var periodic = october
        periodic.rule = rule
        #expect(periodic.colorKey == rule)
        #expect(october.colorKey == october.id)
    }
}
