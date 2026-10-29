import Foundation
import MMCore
import UIKit
import Vision

/// 收據照片的辨識（ios-design §1.2）：OCR 每張都做，同時找電子發票 QR。
enum ReceiptScanner {
    struct Result {
        var text: String
        var invoice: InvoiceQR?
        /// 壓縮過的 JPEG（長邊 2048 px），和文字一起上傳。
        var jpeg: Data
    }

    static func scan(_ image: UIImage) async throws -> Result {
        let resized = image.resized(maxSide: 2048)
        guard let cgImage = resized.cgImage else {
            throw NSError(domain: "ReceiptScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "讀不到這張照片"])
        }
        guard let jpeg = resized.compressedJPEG(maxBytes: 1_000_000) else {
            throw NSError(domain: "ReceiptScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "照片壓縮失敗"])
        }
        // QR 用原圖找：縮小到 2048 px 之後，收據上的小 QR 可能糊到解不出來。
        let original = image.cgImage ?? cgImage
        let originalOrientation = image.cgOrientation
        let resizedOrientation = resized.cgOrientation

        return try await Task.detached(priority: .userInitiated) {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.recognitionLanguages = ["zh-Hant", "en-US", "ja-JP"]
            textRequest.usesLanguageCorrection = true

            let barcodeRequest = VNDetectBarcodesRequest()
            barcodeRequest.symbologies = [.qr]

            try VNImageRequestHandler(cgImage: cgImage, orientation: resizedOrientation).perform([textRequest])
            // 找不到 QR 不是錯誤（一般收據沒有），不要讓它影響文字辨識的結果。
            try? VNImageRequestHandler(cgImage: original, orientation: originalOrientation).perform([barcodeRequest])

            let lines = (textRequest.results ?? []).compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox  // 左下角為原點
                return RecognizedLine(text: candidate.string, minX: box.minX, minY: 1 - box.maxY, height: box.height)
            }
            let payloads = (barcodeRequest.results ?? []).compactMap(\.payloadStringValue)
            return Result(text: ReceiptText.assemble(lines), invoice: invoice(from: payloads), jpeg: jpeg)
        }.value
    }

    /// 發票有左右兩個 QR：左邊是固定欄位開頭，右邊以 ** 開頭。
    static func invoice(from payloads: [String]) -> InvoiceQR? {
        let right = payloads.first { $0.hasPrefix("**") }
        for left in payloads where !left.hasPrefix("**") {
            if let invoice = InvoiceQR.parse(left: left, right: right) { return invoice }
        }
        return nil
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// JPEG 壓到 `maxBytes` 以內（約 1 MB，§1.2）：品質從 0.7 往下試，最低 0.35。
    func compressedJPEG(maxBytes: Int) -> Data? {
        var best: Data?
        for quality in [0.7, 0.5, 0.35] as [CGFloat] {
            guard let data = jpegData(compressionQuality: quality) else { continue }
            best = data
            if data.count <= maxBytes { break }
        }
        return best
    }

    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
