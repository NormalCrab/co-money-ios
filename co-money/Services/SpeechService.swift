// SpeechService.swift
// co-money
//
// Abstraction layer for speech-to-text.
// Current implementation: iOS Speech framework (zh-TW locale handles mixed Chinese/English)
// Future: swap to WhisperSpeechRecognitionService for better multilingual accuracy

import Foundation
import Speech
import AVFoundation

// MARK: - SpeechRecognitionService Protocol
// 语音识别服务协议 - 协议导向设计
//
// 这个协议定义了任何语音识别实现必须遵循的接口。
// 这允许我们在不同的实现之间轻松切换（iOS原生、Whisper API、自定义后端）
//
// This protocol defines the interface for any speech-to-text implementation.
// Using protocol abstraction allows us to easily swap implementations without
// changing the UI code - just change one line in VoiceInputView!
//
// Benefits of Protocol-Oriented Design:
// 协议导向设计的好处：
// 1. Decoupling: UI doesn't depend on specific implementation (iOS vs Whisper)
//    解耦：UI不依赖于具体的实现（iOS vs Whisper）
// 2. Testability: Easy to create mock implementations for unit tests
//    可测试性：便于为单元测试创建模拟实现
// 3. Flexibility: Swap implementations at runtime if needed
//    灵活性：如果需要，可以在运行时交换实现
// 4. Future-proofing: Add new implementations without touching existing code
//    未来保证：添加新实现而不触及现有代码

protocol SpeechRecognitionService: AnyObject {
    // AnyObject: 限制协议只能由class实现（不能是struct/enum）
    // 原因：需要weak引用（避免保留循环）和长生命周期对象
    // Reason: needs weak references (avoid retain cycles) and long-lived objects

    /// Transcribe raw audio data to text
    /// 将原始音频数据转录为文本
    ///
    /// - Parameter audioData: Raw audio file data (M4A format)
    ///   原始音频文件数据（M4A格式）
    /// - Returns: Transcribed text string
    ///   返回：转录的文本字符串
    /// - Throws: SpeechError if transcription fails
    ///   抛出：如果转录失败抛出SpeechError
    ///
    /// async throws: 异步函数会抛出异常
    /// This is modern Swift concurrency (async/await, introduced in iOS 13)
    /// 这是现代Swift并发（async/await，iOS 13引入）
    func transcribe(audioData: Data) async throws -> String
}

// MARK: - iOS Native Speech (Default Implementation)
// iOS原生语音识别 - 默认实现
//
// 使用iOS内置的Speech.framework进行语音识别。
// 优点：无需联网、无额外成本、响应快速
// 缺点：多语言支持不如Whisper好
//
// Uses iOS built-in Speech framework for offline speech recognition.
// Pros: Works offline, no API costs, fast local processing
// Cons: Not as accurate for multilingual content as Whisper
//
// Frameworks Used:
// - Speech: iOS framework for speech recognition (SFSpeechRecognizer)
//   iOS speech recognition framework
// - AVFoundation: For audio format handling (M4A codec, etc)
//   音频格式处理

final class IOSSpeechRecognitionService: SpeechRecognitionService {
    // zh-TW recognizer handles mixed Chinese/English better than pure en-US
    // zh-TW识别器比纯en-US更好地处理混合中文/英文
    // Mandarin Chinese (Traditional) locale provides better multilingual support
    // 繁体中文（台湾）语言环境提供更好的多语言支持
    private let recognizer: SFSpeechRecognizer?

    /// Initialize with a specific locale
    /// 使用特定语言环境初始化
    ///
    /// - Parameter locale: Defaults to zh-TW (Traditional Chinese)
    ///   参数locale：默认为zh-TW（繁体中文）
    ///
    /// Why zh-TW instead of en-US or zh-Hans?
    /// 为什么选择zh-TW而不是en-US或zh-Hans？
    /// - zh-TW provides the most balanced multilingual recognition
    ///   zh-TW提供最平衡的多语言识别
    /// - Works well for both Chinese and English
    ///   对中文和英文都很有效
    /// - iOS prioritizes the set locale, then falls back gracefully
    ///   iOS优先使用设置的语言环境，然后优雅地回退
    init(locale: Locale = Locale(identifier: "zh-TW")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Transcribe audio data to text using iOS Speech framework
    /// 使用iOS Speech框架将音频数据转录为文本
    ///
    /// Implementation details:
    /// 实现细节：
    /// 1. Check recognizer is available (requires user permission + iOS 10+)
    ///    检查识别器是否可用（需要用户权限和iOS 10+）
    /// 2. Write audio data to temporary file (SFSpeechRecognizer requires URL, not raw data)
    ///    将音频数据写入临时文件（SFSpeechRecognizer需要URL，而非原始数据）
    /// 3. Create SFSpeechURLRecognitionRequest pointing to the file
    ///    创建指向文件的SFSpeechURLRecognitionRequest
    /// 4. Use withCheckedThrowingContinuation to bridge callback-based API to async/await
    ///    使用withCheckedThrowingContinuation将基于回调的API桥接到async/await
    func transcribe(audioData: Data) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        // Write audio data to a temp file for URL-based recognition
        // 将音频数据写入临时文件，用于基于URL的识别
        // SFSpeechRecognizer只接受URL，不能直接处理Data对象
        // SFSpeechRecognizer only accepts URL input, not raw Data
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        try audioData.write(to: tempURL)

        // Ensure temp file is deleted when we're done
        // 确保完成后删除临时文件
        // defer: 函数返回前必定执行（类似try-finally）
        // defer: guaranteed to execute before function returns (like try-finally)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Create speech recognition request
        // 创建语音识别请求
        let request = SFSpeechURLRecognitionRequest(url: tempURL)

        // Don't report partial results, just wait for final result
        // 不报告部分结果，只等待最终结果
        // 设为true会在说话时实时返回中间结果，但我们需要完整的转录文本
        // If true, recognizer would report text as user is still speaking
        request.shouldReportPartialResults = false

        // Bridge callback-based API to async/await
        // 将基于回调的API桥接到async/await
        //
        // withCheckedThrowingContinuation: Swift concurrency tool
        // withCheckedThrowingContinuation：Swift并发工具
        // - Takes a closure that receives a continuation
        ///  接收一个获取continuation的闭包
        // - The closure can call continuation.resume(returning:) to return a value
        ///  闭包可以调用continuation.resume(returning:)返回值
        // - Or continuation.resume(throwing:) to throw an error
        ///  或continuation.resume(throwing:)抛出错误
        // - Compiler checks that resume() is called exactly once
        ///  编译器检查resume()恰好被调用一次
        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            // Start recognition task
            // 启动识别任务
            recognizer.recognitionTask(with: request) { result, error in
                // Guard against multiple resume calls (should never happen, but safe)
                // 防止多次resume调用（不应该发生，但是安全的）
                guard !didResume else { return }

                // Handle error
                // 处理错误
                if let error {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }

                // Handle successful final result
                // 处理成功的最终结果
                if let result, result.isFinal {
                    didResume = true
                    // Return the best transcription as string
                    // 返回最佳转录为字符串
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}

// MARK: - Whisper (Future Backend / OpenAI Integration)
// Whisper 语音识别 - 未来后端/OpenAI集成
//
// Whisper是OpenAI的高精度多语言语音识别模型。
// 虽然比本地iOS识别需要网络，但精度更高，特别是对于复杂的混合语言内容。
//
// Whisper is OpenAI's high-accuracy multilingual speech recognition model.
// While it requires network connectivity, it's much more accurate than iOS native
// recognition, especially for complex multilingual content (Chinese + English).
//
// Two deployment options:
// 两种部署选项：
// 1. Direct OpenAI API: Call OpenAI's servers directly (simple, but costs money)
//    直接OpenAI API：直接调用OpenAI服务器（简单，但需要付费）
// 2. Custom backend: Your own server running Whisper (more control, privacy)
//    自定义后端：运行Whisper的自己的服务器（更多控制，隐私）
//
// HOW TO SWITCH FROM iOS TO WHISPER:
// 如何从iOS切换到Whisper：
// In VoiceInputView, replace:
//   @State private var sttService: any SpeechRecognitionService = IOSSpeechRecognitionService()
// with:
//   @State private var sttService: any SpeechRecognitionService = WhisperSpeechRecognitionService(apiKey: "YOUR_OPENAI_KEY")
//   or
//   @State private var sttService: any SpeechRecognitionService = WhisperSpeechRecognitionService(backendURL: "https://codai8.com/api/transaction-parsers/upload/audio/")
//
// That's it! No other code changes needed thanks to protocol abstraction!
// 仅此而已！由于协议抽象，不需要其他代码更改！

final class WhisperSpeechRecognitionService: SpeechRecognitionService {
    // Store either OpenAI API key or custom backend URL
    // 存储OpenAI API密钥或自定义后端URL
    private let apiKey: String?
    private let backendURL: String?

    /// Initialize with direct OpenAI Whisper API
    /// 使用直接OpenAI Whisper API初始化
    ///
    /// - Parameter apiKey: Your OpenAI API key
    ///   你的OpenAI API密钥
    ///
    /// Cost: $0.02 per minute of audio at 2024 prices
    /// 成本：2024年价格为每分钟音频$0.02
    init(apiKey: String) {
        self.apiKey = apiKey
        self.backendURL = nil
    }

    /// Initialize with custom backend endpoint
    /// 使用自定义后端端点初始化
    ///
    /// - Parameter backendURL: Your server's Whisper endpoint URL
    ///   你的服务器Whisper端点URL
    ///
    /// Your backend should:
    /// 你的后端应该：
    /// - Accept multipart form-data POST with audio file
    /// - Run Whisper model
    /// - Return JSON: { "text": "transcribed text" }
    init(backendURL: String) {
        self.apiKey = nil
        self.backendURL = backendURL
    }

    /// Transcribe audio using Whisper (via OpenAI or custom backend)
    /// 使用Whisper转录音频（通过OpenAI或自定义后端）
    func transcribe(audioData: Data) async throws -> String {
        // Route to the appropriate Whisper backend
        // 路由到适当的Whisper后端
        if let apiKey {
            return try await transcribeViaOpenAI(data: audioData, apiKey: apiKey)
        } else if let url = backendURL {
            return try await transcribeViaBackend(data: audioData, url: url)
        }
        throw SpeechError.notConfigured
    }

    /// Send audio to OpenAI's Whisper API
    /// 将音频发送到OpenAI的Whisper API
    ///
    /// Multipart form-data request format:
    /// 多部分form-data请求格式：
    /// This is how file uploads work on the web. We're manually constructing
    /// the multipart body because URLRequest doesn't handle multipart for us.
    /// 这是网络上文件上传的方式。我们手动构造多部分主体，因为URLRequest不会为我们处理多部分。
    private func transcribeViaOpenAI(data: Data, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw SpeechError.configError
        }

        // Create multipart boundary (random string separating form fields)
        // 创建多部分边界（分隔表单字段的随机字符串）
        let boundary = "Boundary-\(UUID().uuidString)"

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Manually build multipart form body
        // 手动构建多部分表单主体
        var body = Data()
        let nl = "\r\n"

        // model field: specify whisper-1 model
        // 模型字段：指定whisper-1模型
        body += "--\(boundary)\(nl)Content-Disposition: form-data; name=\"model\"\(nl)\(nl)whisper-1\(nl)".data(using: .utf8)!

        // language hint for better Chinese/English handling
        // 语言提示，以更好地处理中文/英文
        // Telling Whisper to expect Chinese helps it better recognize mixed Chinese/English
        // 告诉Whisper期望中文有助于它更好地识别混合中文/英文
        body += "--\(boundary)\(nl)Content-Disposition: form-data; name=\"language\"\(nl)\(nl)zh\(nl)".data(using: .utf8)!

        // audio file field
        // 音频文件字段
        body += "--\(boundary)\(nl)Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\(nl)".data(using: .utf8)!
        body += "Content-Type: audio/m4a\(nl)\(nl)".data(using: .utf8)!
        body += data  // raw audio bytes
        body += "\(nl)--\(boundary)--\(nl)".data(using: .utf8)!
        req.httpBody = body

        // Send request and get response
        // 发送请求并获取响应
        // URLSession.shared.data returns (Data, URLResponse) tuple
        // URLSession.shared.data返回(Data, URLResponse)元组
        let (responseData, _) = try await URLSession.shared.data(for: req)

        // Parse JSON response: { "text": "transcribed string" }
        // 解析JSON响应
        struct WhisperResponse: Decodable { let text: String }
        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: responseData)
        return decoded.text
    }

    /// Send audio to custom backend running Whisper
    /// 将音频发送到运行Whisper的自定义后端
    ///
    /// TODO: implement once backend Whisper endpoint is ready
    /// 待办事项：一旦后端Whisper端点准备好就实现
    ///
    /// Expected request: same multipart format as OpenAI
    /// 预期请求：与OpenAI相同的多部分格式
    /// Expected response: { "text": "transcribed string" }
    /// 预期响应：{ "text": "转录字符串" }
    private func transcribeViaBackend(data: Data, url: String) async throws -> String {
        // TODO: implement once backend Whisper endpoint is ready and returns transcription
        throw SpeechError.notImplemented
    }
}

// MARK: - Voice Recorder
// 语音录音机 - 处理音频录制
//
// 这个类管理麦克风录音。它使用AVAudioEngine捕获音频数据并保存为M4A文件。
// 使用@Observable宏使其与SwiftUI集成，以便在录制状态改变时自动更新UI。
//
// This class manages microphone recording using AVAudioEngine (Apple's low-level audio API).
// The @Observable macro makes it work with SwiftUI - when isRecording changes, all observing
// SwiftUI views automatically re-render (no need for @State binding).
//
// @Observable (iOS 17+):
// - Automatically notifies SwiftUI of state changes
//   在状态改变时自动通知SwiftUI
// - Cleaner than @StateObject/@EnvironmentObject in many cases
//   在许多情况下比@StateObject/@EnvironmentObject更清晰
// - Part of SwiftUI's modern observation system
//   SwiftUI现代观察系统的一部分

@Observable
final class VoiceRecorder {
    // Observable properties - SwiftUI watches these for changes
    // 可观察属性 - SwiftUI监视这些变化

    /// Whether audio is currently being recorded
    /// 当前是否正在录制音频
    var isRecording = false

    /// Error message if recording fails
    /// 如果录制失败的错误消息
    var errorMessage: String?

    // MARK: Audio Engine
    // Audio engine is Apple's low-level audio API
    // Audio engine是Apple的低级音频API
    // - Provides direct access to microphone and audio processing
    ///  提供对麦克风和音频处理的直接访问
    // - More powerful than AVAudioRecorder but requires more setup
    ///  比AVAudioRecorder更强大，但需要更多设置
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?       // File we're writing audio to
    private var tempURL: URL?                 // Path to temp audio file

    // MARK: - Permission Management
    // 权限管理 - 请求访问麦克风和语音识别权限

    /// Request microphone recording permission from user
    /// 向用户请求麦克风录制权限
    ///
    /// - Returns: true if user granted permission, false if denied
    ///   返回值：如果用户授予权限则为true，如果被拒绝则为false
    ///
    /// Uses AVAudioApplication.requestRecordPermission for backward compatibility
    /// 使用AVAudioApplication.requestRecordPermission以获得向后兼容性
    ///
    /// withCheckedContinuation: Bridge callback-based permission API to async/await
    /// withCheckedContinuation：将基于回调的权限API桥接到async/await
    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Request speech recognition permission from user
    /// 向用户请求语音识别权限
    ///
    /// - Returns: true if user authorized speech recognition, false otherwise
    ///   返回值：如果用户授权语音识别则为true，否则为false
    ///
    /// Required for using Speech.framework for transcription
    /// 使用Speech.framework进行转录需要
    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Recording Control
    // 录音控制 - 启动和停止录音

    /// Start recording audio from the microphone
    /// 开始从麦克风录制音频
    ///
    /// Throws: If audio session setup fails
    /// 抛出：如果音频会话设置失败
    ///
    /// Setup steps:
    /// 设置步骤：
    /// 1. Configure AVAudioSession (system-wide audio settings)
    ///    配置AVAudioSession（系统范围的音频设置）
    /// 2. Create temporary file for audio output
    ///    为音频输出创建临时文件
    /// 3. Attach tap to input node to capture microphone data
    ///    将tap连接到输入节点以捕获麦克风数据
    /// 4. Start AVAudioEngine
    ///    启动AVAudioEngine
    func startRecording() throws {
        // Configure audio session for recording
        // 配置音频会话进行录制
        let session = AVAudioSession.sharedInstance()

        // .record: 配置用于录制的会话
        // .measurement: 最小化用户界面声音（警报、系统声音会被抑制）
        // .duckOthers: 如果其他应用在播放，自动降低其音量
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Create temporary file for audio output
        // 为音频输出创建临时文件
        // M4A (MPEG4-AAC) 是iOS推荐的音频格式，提供很好的压缩和质量平衡
        // M4A is iOS recommended format with good compression and quality balance
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        tempURL = url

        // Audio format settings: MP4 AAC codec
        // 音频格式设置：MP4 AAC编解码器
        let settings: [String: Any] = [
            AVFormatIDKey:             Int(kAudioFormatMPEG4AAC),  // Codec
            AVSampleRateKey:           44100,                       // 44.1kHz (good quality)
            AVNumberOfChannelsKey:     1,                           // Mono (voice only)
            AVEncoderAudioQualityKey:  AVAudioQuality.high.rawValue // High quality encoding
        ]
        audioFile = try AVAudioFile(forWriting: url, settings: settings)

        // Set up audio engine to capture microphone input
        // 设置音频引擎以捕获麦克风输入
        let inputNode = audioEngine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)

        // Install tap: callback that receives audio buffers as they're recorded
        // 安装tap：接收录制时的音频缓冲区的回调
        // bufferSize 1024: 每次回调捡取1024个音频采样
        // This closure is called repeatedly as audio comes in
        // 这个闭包在音频进来时被重复调用
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        // Prepare and start the audio engine
        // 准备并启动音频引擎
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    /// Stop recording and return the audio data
    /// 停止录制并返回音频数据
    ///
    /// - Returns: Audio file data (M4A format), or nil if error occurred
    ///   返回值：音频文件数据（M4A格式），如果出错则为nil
    ///
    /// Cleanup:
    /// 清理：
    /// - Stop audio engine
    ///   停止音频引擎
    /// - Remove the audio input tap
    ///   移除音频输入tap
    /// - Reset audio session
    ///   重置音频会话
    /// - Load and return the audio file data
    ///   加载并返回音频文件数据
    /// - Delete temporary file
    ///   删除临时文件
    func stopRecording() -> Data? {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false

        // Load the audio data from temporary file
        // 从临时文件加载音频数据
        guard let url = tempURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        tempURL = nil
        return data
    }
}

// MARK: - Error Types
// 错误类型 - 语音识别特有的错误

enum SpeechError: Error, LocalizedError {
    /// Speech recognizer is not available on this device
    /// 语音识别器在此设备上不可用
    case recognizerUnavailable

    /// User denied microphone or speech recognition permission
    /// 用户拒绝了麦克风或语音识别权限
    case noPermission

    /// Whisper service is not configured (no API key or backend URL)
    /// Whisper服务未配置（无API密钥或后端URL）
    case notConfigured

    /// Error in configuration (e.g., invalid URL)
    /// 配置中的错误（例如，无效的URL）
    case configError

    /// Backend Whisper feature not yet implemented
    /// 后端Whisper功能尚未实现
    case notImplemented

    /// User-friendly error description
    /// 用户友好的错误描述
    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "語音辨識不可用 (Speech recognizer unavailable)"
        case .noPermission:          return "麥克風或語音辨識權限被拒絕"
        case .notConfigured:         return "Whisper service not configured"
        case .configError:           return "Configuration error"
        case .notImplemented:        return "Backend Whisper not yet implemented"
        }
    }
}
