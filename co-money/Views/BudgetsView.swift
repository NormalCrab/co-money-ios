import MMCore
import SwiftUI

/// 預算（設計畫布「Budgets」）：選定月份的 tag。新增、修改、封存都在手機上做（N6、N7）。
struct BudgetsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Tag?
    @State private var creatingOnce = false
    @State private var creatingPeriodic = false
    @State private var showArchived = false
    @State private var archived: [Tag] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfflineBanner()
                List {
                    Section {
                        ForEach(model.monthTags) { tag in
                            Button { editing = tag } label: { BudgetRow(tag: tag) }
                                .buttonStyle(.plain)
                        }
                        if model.monthTags.isEmpty {
                            Text("這個月沒有預算，按右上角的「＋」新增。").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("一筆交易可以屬於多個 tag，各 tag 的花費不能相加。")
                    }

                    if showArchived {
                        Section("已封存") {
                            ForEach(archived.filter { model.overlapsMonth($0) }) { tag in
                                Button { editing = tag } label: { BudgetRow(tag: tag) }
                                    .buttonStyle(.plain)
                                    .opacity(0.6)
                            }
                        }
                    }

                    Section {
                        NavigationLink("週期預算") { TagRulesView() }
                    } footer: {
                        Text("週期預算會依頻率每一期自動產生一個預算，例如每月的伙食費。")
                    }
                }
                .refreshable {
                    await model.refreshLedgerData()
                    await loadArchived()
                }
            }
            .navigationTitle("預算")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MonthMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("新增預算", systemImage: "plus") { creatingOnce = true }
                        Button("新增週期預算", systemImage: "arrow.triangle.2.circlepath") { creatingPeriodic = true }
                        Toggle("顯示已封存", isOn: $showArchived)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: showArchived) { _, _ in Task { await loadArchived() } }
            .sheet(item: $editing) { tag in
                BudgetEditor(editing: tag) { await loadArchived() }
            }
            .sheet(isPresented: $creatingOnce) {
                BudgetEditor { await loadArchived() }
            }
            .sheet(isPresented: $creatingPeriodic) {
                TagRuleEditor()
            }
        }
    }

    private func loadArchived() async {
        guard showArchived, let ledger = model.selectedLedger else { return }
        if let list = try? await model.api.archivedTags(ledger: ledger.id) { archived = list }
    }
}

struct BudgetRow: View {
    let tag: Tag

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tag.name).font(.headline)
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

    private var period: String {
        guard let start = tag.periodStart, let end = tag.periodEnd else { return "一次性" }
        if start.year == end.year {
            return "\(start.month)/\(start.day) ~ \(end.month)/\(end.day)"
        }
        return "\(start.year)/\(start.month)/\(start.day) ~ \(end.year)/\(end.month)/\(end.day)"
    }
}
