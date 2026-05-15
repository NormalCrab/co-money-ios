// OCRService.swift
// co-money
// Receipt OCR using iOS Vision framework
// Supports Traditional Chinese, Simplified Chinese, and English simultaneously

import Foundation
import Vision
import UIKit

// MARK: - OCRService Overview
// OCR服务 - 使用iOS Vision框架的光学字符识别
//
// 这个服务使用Apple's Vision框架从收据或其他图像中提取文本。
// Vision框架使用机器学习来识别图像中的文本，支持多语言。
// 通过@Observable宏与SwiftUI集成，以便UI可以观察处理状态。
//
// This service extracts text from images (like receipts) using Apple's Vision framework,
// which uses on-device machine learning to recognize text in images.
// It supports multiple languages simultaneously: Traditional Chinese, Simplified Chinese, English.
//
// Key Framework: Vision
// - Apple's computer vision framework (iOS 11+)
// - VNRecognizeTextRequest: Machine learning-based text recognition
// - Runs entirely on-device (no network needed, privacy-friendly)
// - Supports 50+ languages
//
// Design Pattern: @Observable
// - Modern SwiftUI observation system (iOS 17+)
// - @Observable classes automatically notify SwiftUI of state changes
// - When isProcessing changes, all observing SwiftUI views re-render automatically
// - No need for @State/@StateObject binding complexity
//
// Performance Consideration: Background Thread
// - Vision.perform() is CPU-heavy and blocks the calling thread
// - We run it on a background thread to keep UI responsive
// - Task.detached(priority: .userInitiated) handles this

@Observable
final class OCRService {
    // Observable state property
    // 可观察的状态属性 - 当值改变时SwiftUI自动更新
    // Indicates whether OCR processing is currently running
    // 指示OCR处理当前是否正在运行
    var isProcessing = false

    // MARK: - Text Recognition Method

    /// Extract text from a UIImage using VNRecognizeTextRequest.
    /// 使用VNRecognizeTextRequest从UIImage中提取文本。
    /// Runs on a detached background task to avoid blocking the main thread.
    /// 在分离的后台任务上运行，避免阻塞主线程。
    ///
    /// - Parameter image: UIImage to extract text from
    ///   参数image：要提取文本的UIImage
    ///
    /// - Returns: String containing all recognized text, with lines separated by newlines
    ///   返回值：包含所有识别文本的字符串，各行用换行符分隔
    ///
    /// - Throws: OCRError if image is invalid or recognition fails
    ///   抛出：如果图像无效或识别失败，抛出OCRError
    ///
    /// Usage Example:
    /// 使用示例：
    ///     let ocr = OCRService()
    ///     let image = UIImage(named: "receipt")!
    ///     let text = try await ocr.recognizeText(from: image)
    ///     print(text) // "Total: $50.00\nDate: 2024-01-15\n..."
    ///
    /// Process Flow:
    /// 处理流程：
    /// 1. Guard image has valid CGImage representation
    ///    确保image有有效的CGImage表示
    /// 2. Set isProcessing = true (notify SwiftUI we're busy)
    ///    设置isProcessing = true（通知SwiftUI我们很忙）
    /// 3. Dispatch to background thread with defer cleanup
    ///    分派到后台线程，使用defer清理
    /// 4. Create VNRecognizeTextRequest with language settings
    ///    使用语言设置创建VNRecognizeTextRequest
    /// 5. Execute request synchronously (blocks, but on background thread)
    ///    同步执行请求（阻塞，但在后台线程上）
    /// 6. Extract text from results
    ///    从结果中提取文本
    /// 7. Return text and set isProcessing = false
    ///    返回文本并设置isProcessing = false
    func recognizeText(from image: UIImage) async throws -> String {
        // Guard against invalid image
        // 防止无效图像
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        // Set processing flag for UI
        // 设置UI处理标志
        isProcessing = true

        // defer: guaranteed to execute when function exits (like try-finally)
        // defer: 函数退出时保证执行（如同try-finally）
        // This ensures isProcessing is reset even if an error is thrown
        // 这确保即使抛出错误，isProcessing也会重置
        defer { isProcessing = false }

        // Task.detached: Run on a background thread
        // Task.detached：在后台线程上运行
        //
        // Why detached?
        // 为什么分离？
        // - Vision.perform() is CPU-heavy and synchronous
        ///  Vision.perform()是CPU密集的且同步的
        // - Blocks the current thread until recognition completes
        ///  阻塞当前线程直到识别完成
        // - If run on main thread, would freeze the UI
        ///  如果在主线程上运行，会冻结UI
        // - detached(priority: .userInitiated) tells OS: "This is user-triggered work, prioritize it"
        ///  detached(priority: .userInitiated)告诉OS："这是用户触发的工作，优先处理它"
        //
        // .value: waits for detached task to complete and returns its result
        // .value: 等待分离任务完成并返回其结果
        return try await Task.detached(priority: .userInitiated) {
            // Create text recognition request
            // 创建文本识别请求
            let request = VNRecognizeTextRequest()

            // Configure language recognition
            // 配置语言识别
            // recognitionLanguages: Array of BCP-47 language codes
            // recognitionLanguages：BCP-47语言代码数组
            // - "zh-Hant": 繁体中文（传统，用于台湾/香港）
            //   Traditional Chinese (Taiwan/Hong Kong)
            // - "zh-Hans": 简体中文（用于大陆）
            //   Simplified Chinese (Mainland China)
            // - "en-US": 英文（美国）
            //   English (US)
            // Vision will recognize all three simultaneously
            // Vision将同时识别所有三种
            request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]

            // Recognition quality setting
            // 识别质量设置
            // .accurate: 高精度（较慢但准确，推荐用于重要文本如收据）
            // Other option: .fast (less accurate, faster)
            request.recognitionLevel = .accurate

            // Enable language correction
            // 启用语言修正
            // Vision will try to correct obvious OCR errors
            // Vision将尝试纠正明显的OCR错误
            // Helps with recognizing handwritten or poor quality text
            // 有助于识别手写或低质量文本
            request.usesLanguageCorrection = true

            // Create handler to process image
            // 创建处理器来处理图像
            // VNImageRequestHandler wraps the image and applies requests to it
            // VNImageRequestHandler包装图像并将请求应用于它
            // options: [:] means no special processing (other options: orientation, CIImage context, etc.)
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            // Execute the request synchronously
            // 同步执行请求
            // handler.perform() blocks until recognition completes
            // 在识别完成前阻塞
            // Safe to block here because we're on a background thread
            // 在后台线程上阻塞是安全的
            try handler.perform([request])

            // Extract results from request
            // 从请求中提取结果
            // request.results returns array of VNRecognizedTextObservation
            // request.results返回VNRecognizedTextObservation数组
            guard let observations = request.results, !observations.isEmpty else {
                return ""
            }

            // Convert observations to text strings
            // 将observations转换为文本字符串
            return observations
                // topCandidates(1): Get top 1 recognition result (most confident)
                // topCandidates(1)：获取排名前1的识别结果（最自信）
                // Vision can return multiple candidates in order of confidence
                // Vision可以按置信度顺序返回多个候选项
                // We take the first (most confident) one
                // 我们采用第一个（最自信的）
                .compactMap { $0.topCandidates(1).first?.string }
                // joined(separator: "\n"): Combine all text lines into one string
                // 用换行符连接所有文本行
                // Each VNRecognizedTextObservation represents one line of text
                // 每个VNRecognizedTextObservation代表一行文本
                .joined(separator: "\n")
        }.value
    }
}

// MARK: - Error Handling
// 错误处理 - OCR特定的错误类型

/// Errors specific to OCR operations
/// OCR操作特有的错误
enum OCRError: Error, LocalizedError {
    /// The image passed to OCR is invalid or cannot be processed
    /// 传递给OCR的图像无效或无法处理
    /// Possible causes: image is nil, corrupted, or has unsupported format
    /// 可能的原因：图像为nil、损坏或格式不支持
    case invalidImage

    /// No text was found in the image
    /// 在图像中找不到文本
    /// This is different from error: it means OCR succeeded but found nothing
    /// 这与错误不同：表示OCR成功但未找到任何内容
    case noTextFound

    /// User-friendly error description for display in UI
    /// 用于在UI中显示的用户友好的错误描述
    var errorDescription: String? {
        switch self {
        case .invalidImage:  return "無效圖片 (Invalid image)"
        case .noTextFound:   return "圖片中沒有找到文字"
        }
    }
}
