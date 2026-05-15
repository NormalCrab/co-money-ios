// LoginView.swift
// co-money

import SwiftUI

/// LoginView: 認證視圖層級的入口點，處理用戶登入流程
/// LoginView: Entry point for authentication, handles user login flow
///
/// 主要責任 Key Responsibilities:
/// - 管理本地狀態：帳號、密碼、伺服器 URL (Manage local state: username, password, server URL)
/// - 通過 @Environment 注入的 AuthViewModel 與認證系統通信
///   (Communicate with auth system via @Environment-injected AuthViewModel)
/// - 實現可展開/折疊的伺服器設置選項 (Implement collapsible server configuration)
/// - 動畫效果：狀態轉換、錯誤消息淡入淡出、按鈕禁用狀態動畫
///   (Animations: state transitions, error message fading, button disabled state)
/// - 導航角色：NavigationStack 容器，為應用的認證階段提供基礎
///   (Navigation role: NavigationStack container, foundation for auth phase)
struct LoginView: View {
    /// @Environment 屬性包裝器 - 從環境中注入 AuthViewModel 單例
    /// @Environment property wrapper - injects AuthViewModel singleton from environment
    /// 無需初始化，SwiftUI 自動查找並注入
    /// No need to initialize; SwiftUI auto-locates and injects
    @Environment(AuthViewModel.self) private var authVM

    /// @State 屬性包裝器 - 視圖私有的可變狀態，值變化時自動觸發視圖重新渲染
    /// @State property wrapper - view-private mutable state, triggers re-render on change
    /// 帳號輸入 (Username input)
    @State private var username  = ""

    /// 密碼輸入 - SecureField 會安全顯示此值 (Password input - SecureField displays securely)
    @State private var password  = ""

    /// 伺服器 URL 狀態 - 從 KeychainService 初始化或使用預設值
    /// Server URL state - initialized from KeychainService or uses default
    /// 允許用戶自定義 API 端點 (Allows user to customize API endpoint)
    @State private var serverURL: String = KeychainService.shared.serverURL ?? APIClient.defaultServerURL

    /// 控制伺服器 URL 欄位的展開/折疊狀態 (Toggle visibility of server URL field)
    @State private var showServerField = false

    /// 計算屬性 - 根據輸入狀態動態計算是否允許提交
    /// Computed property - dynamically determines if submission is allowed
    /// 邏輯：帳號非空 AND 密碼非空 AND 未在加載中
    /// Logic: username not empty AND password not empty AND not loading
    /// 使用 animation(value:) 修飾符可以自動為按鈕狀態變化添加動畫
    /// Using animation(value:) modifier automatically animates button state changes
    private var canSubmit: Bool { !username.isEmpty && !password.isEmpty && !authVM.isLoading }

    var body: some View {
        /// NavigationStack - SwiftUI 的導航容器，提供基於堆棧的導航
        /// NavigationStack - SwiftUI's navigation container providing stack-based navigation
        /// 在認證階段作為根導航容器 (Serves as root navigation container in auth phase)
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo - 應用品牌標識區塊 (Logo - app branding section)
                VStack(spacing: 10) {
                    /// SF Symbol 圖標 - 系統圖標庫 (SF Symbol - system icon library)
                    /// font(.system(size:)) 控制大小而非使用預設尺寸
                    /// font(.system(size:)) controls size rather than preset sizes
                    Image(systemName: "yensign.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.tint) // 應用主題色 (Apply accent color)

                    Text("co-money")
                        .font(.largeTitle.bold())

                    Text("記帳 · 共享 · 協作")
                        .font(.subheadline)
                        .foregroundStyle(.secondary) // 次要文本顏色 (Secondary text color)
                }

                Spacer()

                // Form - 表單輸入區塊 (Form - input section)
                VStack(spacing: 14) {
                    // Server URL (collapsible) - 可折疊的伺服器設置
                    VStack(spacing: 8) {
                        /// 點擊按鈕時切換伺服器欄位的可見性
                        /// Tap button to toggle server field visibility
                        /// withAnimation 修飾符包裹狀態變化，為切換添加平滑過渡動畫
                        /// withAnimation wrapper adds smooth animation to toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showServerField.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "server.rack")
                                    .font(.caption)
                                Text(serverDisplayLabel) // 計算屬性，動態顯示伺服器標籤
                                    .font(.caption)
                                    .lineLimit(1) // 防止文字換行，超出自動截斷
                                Spacer()
                                /// 箭頭方向隨 showServerField 狀態改變
                                /// Chevron direction changes with showServerField state
                                Image(systemName: showServerField ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain) // 移除預設按鈕樣式 (Remove default button styling)

                        /// 條件性視圖 - 僅當 showServerField 為 true 時顯示
                        /// Conditional view - only displays when showServerField is true
                        /// if 語句在 SwiftUI 中完全支持，用於條件性視圖構造
                        /// if statements fully supported in SwiftUI for conditional view building
                        if showServerField {
                            /// TextField - 單行文本輸入，使用 $ 前綴進行雙向綁定
                            /// TextField - single-line text input with $ prefix for two-way binding
                            /// $ 綁定意味著視圖和狀態雙向同步：
                            /// $ binding means two-way sync between view and state:
                            /// 用戶輸入 → 更新 @State → 視圖重新渲染
                            /// User input → updates @State → view re-renders
                            /// 反之亦然：@State 變化 → TextField 更新
                            /// Vice versa: @State changes → TextField updates
                            TextField("https://your-server.com", text: $serverURL)
                                .textContentType(.URL) // 鍵盤類型優化 (Optimize keyboard)
                                .keyboardType(.URL)
                                .autocorrectionDisabled() // 禁用自動更正 (Disable autocorrect)
                                .textInputAutocapitalization(.never) // 禁用自動大寫
                                .padding()
                                .background(.quaternary) // 背景顏色 (Background)
                                .clipShape(RoundedRectangle(cornerRadius: 12)) // 圓角
                                /// 過渡效果 - 結合淡入和上方移動動畫 (Transition - combined fade and move)
                                /// transition() 定義視圖插入/移除時的動畫
                                /// transition() defines animation when view appears/disappears
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                /// onChange 修飾符 - 監聽狀態變化並執行副作用
                                /// onChange modifier - monitors state changes and runs side effects
                                /// 舊值和新值都可用於邏輯判斷（此處捨棄舊值）
                                /// Old and new values available for logic (old value discarded here)
                                .onChange(of: serverURL) { _, newVal in
                                    // 立即持久化，使 APIClient 能應用新設置
                                    // Persist immediately so APIClient picks it up
                                    let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                                    KeychainService.shared.serverURL = trimmed.isEmpty ? nil : trimmed
                                }
                        }
                    }

                    /// 帳號輸入欄位 (Username input field)
                    /// TextField 的文本直接綁定到 @State username
                    /// TextField text directly binds to @State username
                    TextField("帳號 Username", text: $username)
                        .textContentType(.username) // 提示鍵盤和自動填充系統
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    /// 密碼輸入欄位 - 使用 SecureField 而非 TextField
                    /// Password input field - uses SecureField for security
                    /// SecureField 自動隱藏輸入字符，不顯示純文本
                    /// SecureField automatically masks input characters
                    SecureField("密碼 Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    /// 錯誤消息 - 條件性顯示 (Error message - conditional display)
                    /// authVM.errorMessage 為 nil 時此 VStack 不渲染
                    /// This VStack doesn't render when authVM.errorMessage is nil
                    if let error = authVM.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            /// 淡入淡出過渡 - 錯誤消息出現/消失時的平滑動畫
                            /// Fade transition - smooth animation as error appears/disappears
                            .transition(.opacity)
                    }

                    /// 登入按鈕 (Login button)
                    Button {
                        /// Task 修飾符 - 在後台線程執行異步代碼
                        /// Task modifier - runs async code in background
                        /// await 關鍵字等待異步操作完成並返回主線程
                        /// await keyword waits for async operation and returns to main thread
                        /// authVM.login() 完成後，@State 數據的變化會自動觸發視圖更新
                        /// When authVM.login() completes, @State changes auto-trigger view update
                        Task { await authVM.login(username: username, password: password) }
                    } label: {
                        HStack(spacing: 8) {
                            /// 加載中顯示進度指示器 (Show progress indicator while loading)
                            if authVM.isLoading {
                                ProgressView().tint(.white)
                            }
                            Text("登入 Sign In")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity) // 填滿可用寬度 (Fill available width)
                        .padding()
                        .background(canSubmit ? Color.accentColor : Color.secondary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSubmit) // 禁用按鈕直到驗證通過 (Disable until validation passes)
                    /// 動畫綁定 - 按鈕顏色和狀態隨 canSubmit 變化而動畫變化
                    /// Animation binding - button color/state animates as canSubmit changes
                    /// animation(value:) 指定哪個值的變化觸發動畫
                    /// animation(value:) specifies which value change triggers animation
                    .animation(.easeInOut(duration: 0.2), value: canSubmit)
                }
                .padding(.horizontal)

                Spacer()
                Spacer()
            }
            .padding()
            /// 全局動畫綁定 - 錯誤消息出現時添加動畫
            /// Global animation binding - adds animation when error message appears
            .animation(.easeInOut, value: authVM.errorMessage)
        }
    }

    /// 計算屬性：動態生成伺服器顯示標籤
    /// Computed property: dynamically generates server display label
    /// 用於在按鈕上顯示伺服器信息 (Used to display server info on button)
    /// - 如果是預設 URL，顯示 "伺服器：預設"
    ///   If default URL, show "伺服器：預設"
    /// - 否則提取 URL 的主機名部分 (Otherwise extract hostname)
    private var serverDisplayLabel: String {
        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty || url == APIClient.defaultServerURL {
            return "伺服器：預設"
        }
        // Show just the host portion for cleanliness
        if let host = URL(string: url)?.host {
            return "伺服器：\(host)"
        }
        return "伺服器：\(url)"
    }
}
