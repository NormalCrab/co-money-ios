import MMCore
import SwiftUI

/// 待處理（設計畫布「Inbox」）：解析好等確認的、解析失敗的、需要處理的待上傳、還在等網路的。
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var fixing: OutboxItem?
    @State private var retryError: String?

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            List {
                if model.inboxCount == 0 && model.waitingItems.isEmpty {
                    Text("沒有待處理的項目").foregroundStyle(.secondary)
                }

                ForEach(model.readyJobs) { job in
                    DraftReview(job: job, title: "待確認・\(job.source.label)・\(captured(job))")
                }

                if !model.failedJobs.isEmpty {
                    Section("解析失敗") {
                        ForEach(model.failedJobs) { job in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.text.isEmpty ? job.source.label : job.text).lineLimit(3)
                                Text(job.error).font(.caption).foregroundStyle(Palette.warning)
                                HStack {
                                    Button("重試") { Task { retryError = await model.retry(job) } }
                                        .disabled(model.isOffline)
                                    Spacer()
                                    Button("捨棄", role: .destructive) { Task { await model.discard(job) } }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                if !model.attentionItems.isEmpty {
                    Section("需要處理 \(model.attentionItems.count)") {
                        ForEach(model.attentionItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.operation.title).font(.headline)
                                if case .needsAttention(let message) = item.state {
                                    Text(message).font(.callout).foregroundStyle(Palette.warning)
                                }
                                HStack {
                                    if case .createTransaction = item.operation {
                                        Button("修改") { fixing = item }
                                    }
                                    Spacer()
                                    Button("捨棄", role: .destructive) {
                                        Task { await model.removeFromOutbox(item) }
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                if !model.waitingItems.isEmpty {
                    Section {
                        ForEach(model.waitingItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.operation.title)
                                    Text(DateText.time(item.createdAt, in: model.timeZone))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(model.isOffline ? "等待網路" : "等待重試")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("待上傳 \(model.waitingItems.count)・連線後自動送出")
                    }
                }
            }
            .refreshable { await model.syncNow() }
        }
        .navigationTitle("待處理")
        .task { await model.refreshParseJobs() }
        .alert("重試失敗", isPresented: Binding(get: { retryError != nil }, set: { if !$0 { retryError = nil } })) {
            Button("好") { retryError = nil }
        } message: {
            Text(retryError ?? "")
        }
        .sheet(item: $fixing) { item in
            if case .createTransaction(let input) = item.operation {
                DraftEditor(input: input) { updated in
                    Task { await model.resubmit(item, with: .createTransaction(updated)) }
                }
            }
        }
    }

    private func captured(_ job: ParseJob) -> String {
        let timeZone = model.ledgers.first { $0.id == job.ledgerId }?.timeZone ?? model.timeZone
        let day = LocalDate(job.capturedAt, in: timeZone)
        return "\(DateText.shortDay(day, today: model.today)) \(DateText.time(job.capturedAt, in: timeZone)) 記錄"
    }
}
