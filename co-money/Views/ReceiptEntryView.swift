import MMCore
import PhotosUI
import SwiftUI
import UIKit

/// 拍收據（設計畫布「Receipt」，ios-design §1.2）。
///
/// 每張照片都做 OCR；有電子發票 QR 時附上 QR 的資料，總金額以 QR 為準。
struct ReceiptEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var scan: ReceiptScanner.Result?
    @State private var text = ""
    @State private var isScanning = false
    @State private var error: String?
    @State private var upload: ParseJobUpload?
    @State private var capturedAt = Date()

    var body: some View {
        NavigationStack {
            Group {
                if let upload {
                    ParseProgress(upload: upload)
                } else if image == nil {
                    chooser
                } else {
                    review
                }
            }
            .navigationTitle("拍收據")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in
                    showCamera = false
                    if let picked { load(picked) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let picked = UIImage(data: data) else { return }
                    load(picked)
                }
            }
            .onAppear {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
            }
        }
    }

    private var chooser: some View {
        VStack(spacing: 16) {
            Spacer()
            Button {
                showCamera = true
            } label: {
                Label("拍照", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("從相簿選", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
            Text("沒有 QR code 的收據也一樣能用，只靠辨識出的文字。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }

    private var review: some View {
        Form {
            if let image {
                Section {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                }
            }
            if isScanning {
                Section { HStack { ProgressView(); Text("辨識中…") } }
            } else {
                if let invoice = scan?.invoice {
                    Section {
                        HStack {
                            Image(systemName: "qrcode").foregroundStyle(Palette.teal)
                            Text("發票 QR：總計 ")
                            Text("\(invoice.total)").bold()
                            Text(" 元，金額以這個為準")
                        }
                        .font(.subheadline)
                    }
                }
                Section {
                    TextField("辨識出的文字", text: $text, axis: .vertical).lineLimit(4...14)
                } header: {
                    Text("辨識出的文字（可以修改）")
                } footer: {
                    if ReceiptText.isTooLittle(text) {
                        Text("看不清楚，要重拍或手動輸入嗎？").foregroundStyle(Palette.warning)
                    } else {
                        Text("送出後由後端分類與整理描述，好了會出現在「待處理」；沒有網路時會先存著。")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.warning) }
                }
                Section {
                    Button("送出解析", action: submit).bold().frame(maxWidth: .infinity)
                        .disabled(ReceiptText.isTooLittle(text) && scan?.invoice == nil)
                    Button("重拍") {
                        image = nil
                        pickerItem = nil  // 不清掉的話，再選同一張相簿照片不會觸發
                        scan = nil
                        text = ""
                        showCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func load(_ picked: UIImage) {
        image = picked
        capturedAt = Date()
        isScanning = true
        error = nil
        Task {
            defer { isScanning = false }
            do {
                let result = try await ReceiptScanner.scan(picked)
                scan = result
                text = result.text
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func submit() {
        guard let ledger = model.selectedLedger, let scan else { return }
        do {
            let name = try model.saveAttachment(scan.jpeg, extension: "jpg")
            upload = ParseJobUpload(ledgerId: ledger.id, source: .receipt,
                                    text: ReceiptText.compose(ocr: text, invoice: scan.invoice),
                                    capturedAt: capturedAt, imageFile: name)
        } catch {
            self.error = "存照片失敗：\(error.localizedDescription)"
        }
    }
}

/// 相機（SwiftUI 沒有內建的，包一層 UIImagePickerController）。
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
