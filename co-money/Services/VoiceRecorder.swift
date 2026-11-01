import AVFoundation
import Foundation
import Speech

/// 錄音並即時辨識成文字（ios-design §1.1）。
///
/// - 優先用裝置上的辨識（不需要網路，聲音不離開手機）。
/// - 同時把聲音存成 m4a（單聲道 64 kbps），和文字一起上傳，存進 ParseLog 供除錯。
/// - 最長 60 秒。
@MainActor
@Observable
final class VoiceRecorder {
    enum State: Equatable {
        case idle
        case recording
        case finished
        case failed(String)
    }

    static let maxDuration: TimeInterval = 60

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var elapsed: TimeInterval = 0
    /// 最近的音量（0…1），畫波形用。
    private(set) var levels: [Float] = []
    /// 這台手機能不能離線辨識。不能的話，沒網路時只存音檔（之後再辨識，見 §1.1）。
    private(set) var isOnDevice = false
    private(set) var audioFile: URL?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var file: AVAudioFile?
    private var timer: Timer?
    private var startedAt: Date?

    init() {
        // 開始錄音前就要能告訴使用者是在手機上辨識還是線上辨識。
        isOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
    }

    /// 要求麥克風與語音辨識的權限。
    func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            // @Sendable：這個 callback 在背景執行緒被呼叫（見 start() 裡的說明）。
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        return speech && microphone
    }

    func start(saveTo url: URL) {
        guard state != .recording else { return }
        task?.cancel()  // 上一次錄音的最後結果不能混進這次的文字
        transcript = ""
        levels = []
        elapsed = 0
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            isOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
            request.requiresOnDeviceRecognition = isOnDevice
            request.addsPunctuation = true
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                // 和麥克風的聲道數一致（iPhone 是單聲道），不然寫檔時格式對不上。
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 64_000,
            ]
            let file = try AVAudioFile(forWriting: url, settings: settings)
            self.file = file
            audioFile = url

            // 這兩個 callback 由系統在背景執行緒呼叫。在 @MainActor 的方法裡直接寫 closure，
            // Swift 6 會把它當成只能在主執行緒跑，被背景呼叫時直接 crash，所以用 nonisolated 的
            // static 方法產生。
            let onLevel: @Sendable (Float) -> Void = { [weak self] level in
                Task { @MainActor in self?.append(level: level) }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format,
                             block: Self.tap(request: request, file: file, onLevel: onLevel))
            engine.prepare()
            try engine.start()

            let onText: @Sendable (String?, Bool) -> Void = { [weak self] text, failed in
                Task { @MainActor in self?.receive(text: text, failed: failed) }
            }
            task = recognizer?.recognitionTask(with: request, resultHandler: Self.resultHandler(onText))

            startedAt = Date()
            state = .recording
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            state = .failed("沒辦法開始錄音：\(error.localizedDescription)")
            cleanUp()
        }
    }

    /// 放開：停止錄音，文字停在可以編輯的狀態。
    func stop() {
        guard state == .recording else { return }
        request?.endAudio()
        cleanUp()
        state = .finished
    }

    /// 往上滑取消：丟掉錄音。
    func cancel() {
        task?.cancel()
        cleanUp()
        if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
        audioFile = nil
        transcript = ""
        state = .idle
    }

    private func append(level: Float) {
        levels.append(level)
        if levels.count > 40 { levels.removeFirst(levels.count - 40) }
    }

    private func receive(text: String?, failed: Bool) {
        if let text { transcript = text }
        if failed, state == .recording, transcript.isEmpty {
            // 沒網路又不支援離線辨識：音檔照樣存著，文字讓使用者自己打。
            isOnDevice = false
        }
    }

    nonisolated private static func tap(request: SFSpeechAudioBufferRecognitionRequest, file: AVAudioFile,
                                        onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            try? file.write(from: buffer)
            onLevel(level(of: buffer))
        }
    }

    nonisolated private static func resultHandler(_ onText: @escaping @Sendable (String?, Bool) -> Void)
        -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            onText(result?.bestTranscription.formattedString, error != nil)
        }
    }

    private func tick() {
        guard let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        if elapsed >= Self.maxDuration { stop() }
    }

    private func cleanUp() {
        timer?.invalidate()
        timer = nil
        // 不管 engine 有沒有在跑都要拿掉 tap：被打斷（來電、切到別的 app）或啟動失敗時
        // engine 已經停了，tap 還在，下次 installTap 會直接 crash。
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        file = nil  // 釋放 AVAudioFile 才會把檔案寫完
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(1, rms * 8)
    }
}
