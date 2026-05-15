// ReceiptCaptureView.swift
// co-money
// Receipt Capture Flow: 拍照或選擇相片 → Vision OCR → 後端解析 → 預覽 → 儲存
// Take/select receipt photo → Vision OCR → backend parse → preview → save

import SwiftUI
import PhotosUI
import UIKit

/// ReceiptCaptureView: 收據辨識檢視
/// 完整的收據掃描流程：
/// 1. 使用相機拍照或從相簿選擇照片 (Take photo with camera or select from photo library)
/// 2. 使用 Vision OCR 辨識圖片中的文字 (Extract text from image using OCR)
/// 3. 向後端 API 發送辨識文字進行 AI 解析 (Send text to backend for parsing)
/// 4. 預覽解析的交易項目 (Preview parsed transactions)
/// 5. 使用者可以儲存或重新掃描 (User can save or re-scan)
struct ReceiptCaptureView: View {
    // MARK: - Environment: Injected view models
    @Environment(TransactionViewModel.self) private var vm
    @Environment(AccountViewModel.self)     private var accountVM
    @Environment(ProfileViewModel.self)     private var profileVM
    @Environment(\.dismiss)                private var dismiss

    // MARK: - Photo Selection State: 照片選擇狀態 (Photo selection state)
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage:     UIImage?
    @State private var showCamera         = false

    // MARK: - OCR & Parsing State: OCR 和解析狀態 (OCR and parsing state)
    @State private var ocrService  = OCRService()
    @State private var extractedText = ""
    @State private var isOCRing     = false
    @State private var isParsing    = false
    @State private var errorMessage: String?

    // MARK: - Parsed Results: 解析結果和預覽狀態 (Parsing results and preview state)
    @State private var parsedTransactions: [Transaction]?
    @State private var showPreview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                // MARK: Image Preview: 顯示選擇的收據照片 (Show selected receipt photo)
                imagePreview

                // MARK: Extracted Text: 顯示 OCR 辨識結果 (Show OCR results)
                extractedTextSection

                Spacer()

                // MARK: Bottom Actions: 拍照、相簿、解析按鈕 (Camera, gallery, parse buttons)
                bottomActions
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
            .navigationTitle("收據辨識 Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: Cancel Button: 關閉收據掃描檢視 (Close receipt capture view)
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            // MARK: Photo Picker: 當選擇相簿中的照片時 (When photo is selected from library)
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadAndProcess(from: item) }
            }
            // MARK: Camera Sheet: 顯示相機介面 (Show camera interface)
            .sheet(isPresented: $showCamera) {
                CameraPickerView(image: $capturedImage)
                    .ignoresSafeArea()
            }
            // MARK: Capture Processing: 當相機拍照完成時 (When camera photo is captured)
            .onChange(of: capturedImage) { _, img in
                if img != nil { Task { await processCurrentImage() } }
            }
            // MARK: Preview Sheet: 顯示解析結果 (Show parsing results preview)
            .sheet(isPresented: $showPreview) {
                if let parsed = parsedTransactions {
                    ParsedTransactionPreviewView(parsedTransactions: parsed)
                        .environment(vm)
                        .environment(accountVM)
                        .environment(profileVM)
                        .onDisappear {
                            dismiss()
                        }
                }
            }
        }
    }

    // MARK: - Sub-Views

    /// Image Preview: 顯示照片或提示選擇照片
    /// Shows photo preview or hint to select photo
    @ViewBuilder
    private var imagePreview: some View {
        if let image = capturedImage {
            // MARK: Photo Display: 顯示選擇的收據照片 (Display selected receipt photo)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        } else {
            // MARK: Empty State: 提示選擇照片 (Hint to select photo)
            VStack(spacing: 16) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                Text("選擇或拍攝收據\nSelect or take receipt photo")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Extracted Text Section: 顯示 OCR 辨識結果
    /// Shows OCR recognition results
    @ViewBuilder
    private var extractedTextSection: some View {
        if isOCRing {
            // MARK: OCR In Progress: 正在進行 OCR (OCR in progress)
            HStack(spacing: 8) {
                ProgressView()
                Text("辨識文字中…")
                    .foregroundStyle(.secondary)
            }
        } else if !extractedText.isEmpty {
            // MARK: OCR Results: 顯示辨識出的文字 (Show extracted text)
            VStack(alignment: .leading, spacing: 6) {
                Label("辨識結果", systemImage: "text.viewfinder")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(extractedText)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .padding(10)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }

        // MARK: Error Display: 顯示 OCR 錯誤 (Show OCR errors)
        if let err = errorMessage {
            Text(err).font(.caption).foregroundStyle(.red)
        }
    }

    /// Bottom Actions: 操作按鈕（拍照、相簿、解析）
    /// Action buttons (camera, gallery, parse)
    @ViewBuilder
    private var bottomActions: some View {
        VStack(spacing: 12) {
            // MARK: Parse Button: 當有辨識文字時顯示 (Show when text is available)
            if !extractedText.isEmpty && !isParsing {
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
            }

            // MARK: Parsing Progress: 後端 AI 正在解析 (Backend AI parsing)
            if isParsing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("AI 解析中…")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Camera & Gallery Buttons: 拍照或選擇相簿 (Take photo or select from library)
            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("拍照", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("相簿", systemImage: "photo.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Logic Functions

    /// Load photo from PhotosPickerItem and process
    /// 從相簿選擇器載入照片並處理 (Load and process photo from library)
    ///
    /// NOTE: We only set capturedImage here; the onChange(of: capturedImage) handler
    /// will call processCurrentImage() automatically. Do NOT call processCurrentImage()
    /// directly here to avoid running OCR twice.
    /// 注意：這裡只設定 capturedImage，onChange(of: capturedImage) 會自動觸發 processCurrentImage()。
    /// 不要在這裡直接呼叫 processCurrentImage()，否則 OCR 會執行兩次。
    private func loadAndProcess(from item: PhotosPickerItem?) async {
        guard let item,
              let data  = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        capturedImage = image
        // processCurrentImage() is triggered by onChange(of: capturedImage) below
    }

    /// Process current image: Run OCR on it
    /// 處理當前照片：執行 OCR (Run OCR on current image)
    private func processCurrentImage() async {
        guard let image = capturedImage else { return }
        isOCRing     = true
        errorMessage = nil
        extractedText = ""
        do {
            // MARK: Vision OCR: 使用 Vision 框架辨識文字 (Use Vision framework to extract text)
            extractedText = try await ocrService.recognizeText(from: image)
            if extractedText.isEmpty {
                errorMessage = "圖片中未找到文字"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isOCRing = false
    }

    /// Parse extracted text and show preview
    /// 解析辨識文字並顯示預覽 (Parse text and show preview)
    private func parseAndPreview() async {
        isParsing    = true
        errorMessage = nil
        do {
            // MARK: AI Parsing: 後端 API 進行 AI 解析 (Backend API for parsing)
            let parsed = try await vm.parseOnly(text: extractedText, source: .receipt)
            if parsed.isEmpty {
                errorMessage = "未能從收據中解析出交易"
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

// MARK: - Camera Picker Wrapper
/// UIImagePickerController 的 SwiftUI 包裝器，用於相機功能
/// SwiftUI wrapper for UIImagePickerController for camera functionality
struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    // MARK: Coordinator: UIKit 和 SwiftUI 之間的橋樑 (Bridge between UIKit and SwiftUI)
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: Make Controller: 建立 UIImagePickerController
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    /// Coordinator: 處理相機結果回調
    /// Coordinator class to handle camera result callbacks
    final class Coordinator: NSObject,
                              UIImagePickerControllerDelegate,
                              UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        // MARK: Image Picker Delegate: 相機拍照完成時調用 (Called when photo is taken)
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        // MARK: Cancel Delegate: 使用者取消拍照時調用 (Called when user cancels)
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
