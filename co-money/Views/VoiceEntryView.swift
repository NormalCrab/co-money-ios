import MMCore
import SwiftUI

/// 語音記帳（設計畫布「Voice」，ios-design §1.1）。
///
/// 按住說話、放開停止；往上滑取消。辨識出的文字可以修改再送出。
struct VoiceEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var recorder = VoiceRecorder()
    @State private var text = ""
    @State private var audioName: String?
    @State private var upload: ParseJobUpload?
    @State private var permissionDenied = false
    @State private var cancelling = false
    @State private var capturedAt = Date()
    /// 手指正按在麥克風上。錄音自動停在 60 秒時手指通常還沒放開，
    /// 不能因為手指又動了一下就重新開始錄。
    @State private var pressing = false

    var body: some View {
        NavigationStack {
            Group {
                if let upload {
                    ParseProgress(upload: upload)
                } else {
                    recording
                }
            }
            .navigationTitle("語音記帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        recorder.cancel()
                        dismiss()
                    }
                }
                if upload == nil && recorder.state == .finished {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("送出", action: submit).bold()
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .task {
                permissionDenied = !(await recorder.requestPermission())
            }
            .onChange(of: recorder.transcript) { _, transcript in text = transcript }
            .onChange(of: scenePhase) { _, phase in
                // 錄音中切到別的 app：停下來，文字留著讓使用者回來修改送出。
                if phase != .active, recorder.state == .recording { recorder.stop() }
            }
            .onDisappear {
                // 下滑關掉 sheet：沒送出的錄音檔不能留在手機裡。
                if upload == nil { recorder.cancel() }
            }
        }
    }

    private var recording: some View {
        VStack(spacing: 20) {
            Text(recorder.isOnDevice ? "在手機上辨識・不需要網路" : "使用 Apple 的線上辨識")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("記到：\(model.selectedLedger?.name ?? "")").font(.subheadline)

            if recorder.state == .finished {
                TextField("辨識出的文字", text: $text, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Text("說錯了沒關係，可以直接修改文字再送出。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(recorder.transcript.isEmpty ? "按住下面的按鈕說話，例如「晚餐牛肉麵 180」" : recorder.transcript)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .frame(minHeight: 80)
            }

            Spacer()

            if recorder.state == .recording {
                waveform
                Text(String(format: "%d:%02d / 1:00", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if case .failed(let message) = recorder.state {
                Text(message).foregroundStyle(Palette.warning)
            }
            if permissionDenied {
                Text("需要麥克風和語音辨識的權限，請到「設定」開啟。")
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
                Button("開啟設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote)
            }

            micButton
            Text(recorder.state == .recording ? (cancelling ? "放開取消" : "放開停止・往上滑取消") : "按住說話")
                .font(.footnote)
                .foregroundStyle(cancelling ? Palette.warning : .secondary)
        }
        .padding(.vertical, 24)
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                Capsule().fill(Palette.accent).frame(width: 3, height: max(4, CGFloat(level) * 60))
            }
        }
        .frame(height: 64)
    }

    private var micButton: some View {
        Circle()
            .fill(recorder.state == .recording ? Palette.accent : Palette.accentSoft)
            .frame(width: 88, height: 88)
            .overlay(Image(systemName: "mic.fill").font(.title)
                .foregroundStyle(recorder.state == .recording ? .white : Palette.accentText))
            .scaleEffect(recorder.state == .recording ? 1.1 : 1)
            .animation(.spring(duration: 0.2), value: recorder.state)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressing {
                            pressing = true
                            if recorder.state != .recording && !permissionDenied {
                                discardRecording()  // 重錄：舊的檔案不再需要
                                let file = model.newAttachmentURL(extension: "m4a")
                                audioName = file.name
                                capturedAt = Date()
                                recorder.start(saveTo: file.url)
                            }
                        }
                        cancelling = value.translation.height < -80
                    }
                    .onEnded { _ in
                        pressing = false
                        if cancelling {
                            recorder.cancel()
                            audioName = nil
                        } else {
                            recorder.stop()
                        }
                        cancelling = false
                    }
            )
            .disabled(permissionDenied)
    }

    private func discardRecording() {
        if let audioName {
            try? FileManager.default.removeItem(at: model.attachments.appendingPathComponent(audioName))
        }
        audioName = nil
    }

    private func submit() {
        guard let ledger = model.selectedLedger else { return }
        upload = ParseJobUpload(ledgerId: ledger.id, source: .voice,
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                capturedAt: capturedAt, audioFile: audioName)
    }
}
