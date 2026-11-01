import MMCore
import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    /// refresh token 失效、但還有待上傳資料時的重新登入（§3.3）。
    var isRelogin = false

    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                if isRelogin {
                    Section {
                        Text("登入已過期。還沒上傳的資料都還在，重新登入後會繼續送出。")
                            .font(.callout)
                    }
                }
                Section {
                    TextField("帳號", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密碼", text: $password)
                        .textContentType(.password)
                        .onSubmit(submit)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.warning) }
                }
                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView() } else { Text("登入").bold() }
                            Spacer()
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isSubmitting)
                }
                if !isRelogin {
                    // 切到沒登入過的伺服器後只剩這個畫面，要能在這裡切回去（A8）。
                    Section {
                        Picker("伺服器", selection: Binding(
                            get: { model.server },
                            set: { server in Task { await model.switchServer(to: server) } }
                        )) {
                            ForEach(Server.allCases) { Text($0.label).tag($0) }
                        }
                    } footer: {
                        Text("兩邊的登入和待上傳資料分開保存。")
                    }
                }
                Section {
                    Text("註冊、帳本成員和匯率的設定請到網頁版。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isRelogin ? "重新登入" : "家庭記帳")
        }
        .onAppear {
            if isRelogin { username = model.username }
        }
    }

    private func submit() {
        guard !username.isEmpty, !password.isEmpty else { return }
        isSubmitting = true
        error = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await model.login(username: username, password: password)
            } catch let apiError as APIError {
                error = apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
