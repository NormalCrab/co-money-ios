// VoiceInputView.swift
// co-money
// Voice Input Flow: 按住錄音 → iOS 語音辨識 → 後端解析 → 預覽 → 儲存
// Press-and-hold to record → iOS Speech transcription → backend parse → preview → save

import SwiftUI
import Speech

/// VoiceInputView: 語音輸入檢視
/// 完整的語音輸入流程：
/// 1. 請求麥克風和語音辨識權限 (Request microphone and speech permissions)
/// 2. 使用 VoiceRecorder 進行錄音 (Press-and-hold to record)
/// 3. 使用 IOSSpeechRecognitionService 進行語音轉文字 (Transcribe with iOS Speech API)
/// 4. 向後端 API 發送文字進行 AI 解析 (Send transcribed text to backend for parsing)
/// 5. 預覽解析結果 (Preview parsed transactions)
/// 6. 使用者可以儲存或重新錄音 (User can save or re-record)
struct VoiceInputView: View {
    // MARK: - Environment: Injected view models
    @Environment(TransactionViewModel.self) private var vm
    @Environment(AccountViewModel.self)     private var accountVM
    @Environment(ProfileViewModel.self)     private var profileVM
    @Environment(\.dismiss)                private var dismiss

    // MARK: - Services: 語音錄音和轉文字服務 (Voice recording and transcription services)
    @State private var recorder:   VoiceRecorder                  = VoiceRecorder()
    @State private var sttService: IOSSpeechRecognitionService = IOSSpeechRecognitionService()

    // MARK: - Permission State: 權限檢查狀態 (Permission check state)
    @State private var permissionGranted = false

    // MARK: - Recording & Transcription State: 錄音和轉文字狀態 (Recording and transcription state)
    @State private var transcribedText   = ""
    @State private var isTranscribing    = false
    @State private var isParsing         = false
    @State private var errorMessage:       String?

    // MARK: - Parsed Results: 解析結果和預覽狀態 (Parsing results and preview state)
    @State private var parsedTransactions: [Transaction]?
    @State private var showPreview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                // MARK: Status Section: 顯示當前狀態（錄音中、轉文字中、已轉錄） (Show current state)
                statusSection

                Spacer()

                // MARK: Mic Button: 當準備好時顯示麥克風按鈕 (Show mic button when ready)
                if transcribedText.isEmpty && permissionGranted && !isTranscribing {
                    micButton
                }

                // MARK: Action Buttons: 當有轉錄文字時顯示操作按鈕 (Show action buttons when text is available)
                if !transcribedText.isEmpty && !isParsing {
                    actionButtons
                }

                // MARK: Error Display: 顯示錯誤訊息 (Show error messages)
                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer().frame(height: 16)
            }
            .padding()
            .navigationTitle("語音輸入 Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: Cancel Button: 關閉語音輸入檢視 (Close voice input view)
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            // MARK: Initial Load: 請求權限 (Request permissions on load)
            .task { await requestPermissions() }
            // MARK: Preview Sheet: 顯示解析結果預覽 (Show parsing results preview)
            .sheet(isPresented: $showPreview, onDismiss: {
                // If preview saved successfully, dismiss voice input too
                // 如果預覽已成功儲存，則關閉語音輸入檢視 (Close voice input if preview saved)
            }) {
                if let parsed = parsedTransactions {
                    ParsedTransactionPreviewView(parsedTransactions: parsed)
                        .environment(vm)
                        .environment(accountVM)
                        .environment(profileVM)
                        .onDisappear {
                            // If transactions were created (vm updated), dismiss self
                            // 如果交易已建立，關閉語音輸入檢視 (Close voice input if transactions created)
                            dismiss()
                        }
                }
            }
        }
    }

    // MARK: - Sub-Views

    /// Status Section: 顯示錄音、轉文字、或已轉錄文字的狀態
    /// Shows recording, transcribing, or transcribed text state
    @ViewBuilder
    private var statusSection: some View {
        if isTranscribing {
            // MARK: Transcribing State: 正在進行語音轉文字 (Transcribing in progress)
            VStack(spacing: 12) {
                ProgressView()
                Text("正在辨識語音…")
                    .foregroundStyle(.secondary)
            }
        } else if isParsing {
            // MARK: Parsing State: 後端 AI 正在解析文字 (Backend AI is parsing text)
            VStack(spacing: 12) {
                ProgressView()
                Text("AI 解析中，請稍候…")
                    .foregroundStyle(.secondary)
            }
        } else if !transcribedText.isEmpty {
            // MARK: Transcribed Text Display: 顯示轉錄後的文字 (Show transcribed text)
            VStack(alignment: .leading, spacing: 10) {
                Label("辨識結果", systemImage: "text.bubble")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(transcribedText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else if !permissionGranted {
            // MARK: No Permission State: 需要請求權限 (Need to request permissions)
            VStack(spacing: 12) {
                Image(systemName: "mic.slash.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("需要麥克風與語音辨識權限\n請至設定中開啟")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        } else {
            // MARK: Ready State: 等待使用者開始錄音 (Ready for user to start recording)
            VStack(spacing: 12) {
                Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                    .scaleEffect(recorder.isRecording ? 1.12 : 1.0)
                    // MARK: Animation: 錄音時脈衝動畫 (Pulse animation when recording)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).speed(recorder.isRecording ? 1 : 0),
                               value: recorder.isRecording)

                Text(recorder.isRecording ? "放開停止 Release to stop" : "按住說話 Hold to speak")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Mic Button: 按住錄音的互動式按鈕
    /// Interactive button for press-and-hold recording
    private var micButton: some View {
        Circle()
            .fill(recorder.isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1))
            .frame(width: 110, height: 110)
            .overlay {
                Image(systemName: "mic.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
            }
            .scaleEffect(recorder.isRecording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
            // MARK: Gesture: 按住開始錄音，放開停止 (Hold to start, release to stop)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !recorder.isRecording { startRecording() } }
                    .onEnded   { _ in if  recorder.isRecording { stopAndTranscribe() } }
            )
    }

    /// Action Buttons: 解析或重新錄音
    /// Parse or re-record buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // MARK: Parse Button: 發送到後端進行 AI 解析 (Send to backend for parsing)
            Button {
                Task { await parseAndPreview() }
            } label: {
                Label("解析記帳 Parse", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // MARK: Re-record Button: 清除文字並重新錄音 (Clear text and re-record)
            Button {
                transcribedText = ""
                errorMessage    = nil
            } label: {
                Text("重新錄音 Re-record")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Logic Functions

    /// Request microphone and speech recognition permissions
    /// 請求麥克風和語音辨識權限 (Request permissions)
    private func requestPermissions() async {
        let mic    = await recorder.requestMicPermission()
        let speech = await recorder.requestSpeechPermission()
        permissionGranted = mic && speech
    }

    /// Start recording audio
    /// 開始錄音 (Start recording)
    private func startRecording() {
        errorMessage = nil
        do {
            try recorder.startRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stop recording and transcribe audio to text
    /// 停止錄音並進行語音轉文字 (Stop recording and transcribe)
    private func stopAndTranscribe() {
        guard let audioData = recorder.stopRecording(), !audioData.isEmpty else {
            errorMessage = "錄音失敗，請重試"
            return
        }
        Task {
            isTranscribing = true
            errorMessage   = nil
            do {
                // MARK: Speech Recognition: 使用 iOS 語音辨識 API (Use iOS Speech API)
                let text = try await sttService.transcribe(audioData: audioData)
                if text.isEmpty {
                    errorMessage = "未偵測到語音，請再試一次"
                } else {
                    transcribedText = text
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranscribing = false
        }
    }

    /// Parse transcribed text and show preview
    /// 解析轉錄文字並顯示預覽 (Parse text and show preview)
    private func parseAndPreview() async {
        isParsing    = true
        errorMessage = nil
        do {
            // MARK: AI Parsing: 後端 API 進行 AI 解析 (Backend API for parsing)
            let parsed = try await vm.parseOnly(text: transcribedText, source: .voice)
            if parsed.isEmpty {
                errorMessage = "未能從文字中解析出交易"
            } else {
                parsedTransactions = parsed
                showPreview = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isParsing = false
    }
}
