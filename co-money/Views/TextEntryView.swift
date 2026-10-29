import MMCore
import SwiftUI

/// 文字輸入（設計畫布「TextEntry」）：一句話寫好幾筆，交給後端解析。
struct TextEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var upload: ParseJobUpload?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let upload {
                    ParseProgress(upload: upload)
                } else {
                    Form {
                        Section {
                            TextField("午餐便當 120，晚上全聯買菜 1280 刷卡", text: $text, axis: .vertical)
                                .lineLimit(3...8)
                                .focused($focused)
                        } header: {
                            Text("用一句話描述，可以一次寫好幾筆")
                        } footer: {
                            Text("記到：\(model.selectedLedger?.name ?? "")")
                        }
                    }
                }
            }
            .navigationTitle("文字輸入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if upload == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("解析", action: submit).bold()
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func submit() {
        guard let ledger = model.selectedLedger else { return }
        upload = ParseJobUpload(ledgerId: ledger.id, source: .manual,
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines), capturedAt: Date())
    }
}
