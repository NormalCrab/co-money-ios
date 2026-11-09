import MMCore
import SwiftUI

/// 預算（設計畫布「Budgets」）：期限和選定月份重疊的 tag（§12：看期限，不看封存，過去的月份也看得到）。
/// 新增、修改、設結束日都在手機上做（N6、N7）。點一個 tag 進明細頁看它的交易，修改在明細頁右上角。
struct BudgetsView: View {
    @Environment(AppModel.self) private var model
    @State private var creatingOnce = false
    @State private var creatingPeriodic = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfflineBanner()
                List {
                    Section {
                        ForEach(model.monthTags) { tag in
                            NavigationLink { TagDetailView(tag: tag) } label: { BudgetRow(tag: tag) }
                        }
                        if model.monthTags.isEmpty {
                            Text("這個月沒有預算，按右上角的「＋」新增。").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("一筆交易可以屬於多個 tag，各 tag 的花費不能相加。")
                    }

                    Section {
                        NavigationLink("週期預算") { TagRulesView() }
                    } footer: {
                        Text("週期預算會依頻率每一期自動產生一個預算，例如每月的伙食費。")
                    }
                }
                .refreshable { await model.refreshLedgerData() }
            }
            .navigationTitle("預算")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MonthMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("新增預算", systemImage: "plus") { creatingOnce = true }
                        Button("新增週期預算", systemImage: "arrow.triangle.2.circlepath") { creatingPeriodic = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $creatingOnce) {
                BudgetEditor()
            }
            .sheet(isPresented: $creatingPeriodic) {
                TagRuleEditor()
            }
        }
    }
}

struct BudgetRow: View {
    let tag: Tag

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TagDot(key: tag.colorKey, size: 10)
                Text(tag.name).font(.headline)
                if tag.isEnded == true {
                    Text("已結束").font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(period).font(.caption).foregroundStyle(.secondary)
            }
            if let budget = tag.budgetAmount {
                BudgetBar(tag: tag)
                HStack {
                    Text("花了 \(tag.spent.display) / \(budget.display)")
                        .font(.subheadline.monospacedDigit())
                    Spacer()
                    if let remaining = tag.remaining {
                        Text(remaining.value >= 0 ? "還剩 \(remaining.display)" : "超支 \(Money(-remaining.value).display)")
                            .font(.subheadline)
                            .foregroundStyle((tag.progress ?? 0) >= 0.9 ? Palette.warning : Palette.income)
                    }
                }
            } else {
                Text("花了 \(tag.spent.display)").font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 4)
    }

    /// 「10/1 ~ 10/31」；一次性 tag：「一次性」「一次性・~ 11/27」。
    private var period: String {
        let range = DateText.period(start: tag.periodStart, end: tag.periodEnd)
        if tag.isPeriodic { return range ?? "" }
        return range.map { "一次性・\($0)" } ?? "一次性"
    }
}
