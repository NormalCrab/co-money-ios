# 給接手的 AI：家庭記帳 iOS（co-money，v2）

使用者是 Alex，用繁體中文溝通。程式註解、commit 訊息、文件也都用繁體中文。

## 1. 這是什麼

家庭記帳 app 的 iOS client，就是 App Store 上的 **co-money**（Bundle ID `com.codai8.co-money`）。
後端是 Django（repo `NormalCrab/django-mm`）。

**這個 repo（`NormalCrab/co-money-ios`）是唯一的開發地點。** v2 是用 SwiftUI 對 v2 API 的完整重寫，
最早在 `NormalCrab/ios-mm` 的 `rewrite/v2` 分支寫成（在沒有 Mac 的 Linux 上），2026-10-29 整合進來
（來源 `ios-mm` 的 `c5cbbfd`），取代了舊的 co-money 程式碼。**`ios-mm` 不要再改**，只當作歷史參考。

定位：**iOS 負責隨手記帳**——看本月、記帳（表單 / 文字 / 語音 / 拍收據）、確認 LLM 解析結果；
網頁能做的設定手機也都要能做（見 `REQUIREMENTS.md` 的 N 組），網頁只多了圖表與報表。

原則（設計文件 §0）：
1. **記下來這件事永遠不會失敗**：沒網路、伺服器忙都先存在手機上（待上傳佇列），之後再送。
2. **LLM 的結果一律經過使用者確認**才變成交易。
3. **存進資料庫的數字由後端算**：手機算的只是預覽；本月花費只算已上傳的。

## 2. 參考資料

- **需求清單**：這個 repo 的 `REQUIREMENTS.md`。每項有編號（A1、L2…）、狀態和驗收方式；
  做完一項、驗收過，就把它的狀態改成「完成」。
- **設計文件**：`NormalCrab/django-mm` 的 `docs/ios-design.md`（main 分支）。所有規則以它為準，
  章節編號（§2.2、§3.3…）在程式註解裡會引用。v2 的資料規則在同一個資料夾的 `docs/v2-design.md`。
- **API schema**：`NormalCrab/django-mm` 的 `frontend/openapi.yml`。`MMCore/Sources/MMCore/Models.swift`
  的型別是對照它手寫的。
- **畫面設計**：Claude 的設計畫布「家庭記帳 iOS 介面」https://claude.ai/artifact/HjGT9TFUH8shiALYjsFn6L
  （Alex 的私人 artifact）。畫板：Main、QuickEntry、TextEntry、Transactions、Budgets、Voice、Receipt、Inbox。
  讀不到的話請 Alex 截圖。
- **後端**：staging `https://newsroom.codai8.com/`，正式 `https://codai8.com/`。

## 3. 結構

```
co-money.xcodeproj  Xcode 專案（直接進 git，不用 XcodeGen）。co-money/ 是同步資料夾，新增檔案會自動加入。
Info.plist          只放 build settings 放不進去的陣列（BGTaskSchedulerPermittedIdentifiers、
                    UIBackgroundModes）；其他 Info.plist 內容由 build settings 產生（GENERATE_INFOPLIST_FILE）。
MMCore/             Swift Package（本地套件），不依賴 UIKit / SwiftUI，Linux 和 Mac 都能測
  Sources/MMCore/
    Values.swift       Money（Decimal，API 用字串）、LocalDate、APICoding（snake_case、ISO 8601）
    Models.swift       API 型別：Ledger、Transaction、TransactionInput、Tag、ParseJob、ParsedDraft…
    HTTP.swift         HTTPTransport、URLSessionTransport、APIError（錯誤分類）、MultipartForm
    AuthSession.swift  登入、token 換發（actor，同時只發一個 refresh）、從 JWT 讀 user_id
    APIClient.swift    每個 endpoint 一個方法；401 時換 token 重送一次
    Outbox.swift       待上傳佇列（actor）+ APIOutboxSender
    InvoiceQR.swift    台灣電子發票 QR 解碼
    ReceiptText.swift  OCR 結果排版、ParseJobWaiter（輪詢）、JSONCache
    Calendar.swift     YearMonth（依帳本時區）、DateText（「今天 10/27（二）」）
  Tests/MMCoreTests/   Swift Testing；LiveTests 對真的後端（平常跳過）
co-money/           SwiftUI app（只能在 Mac 編譯）
  MMApp.swift        @main、TabView、回前景同步、BGAppRefreshTask
  AppModel.swift     @Observable 的全域狀態：登入、資料、快取、待上傳；畫面只呼叫它
  Services/          KeychainTokenStore、Connectivity（NWPathMonitor）、VoiceRecorder（錄音 + Speech）、
                     ReceiptScanner（Vision OCR + QR）、ReminderCenter（提醒記帳的本機通知）
  Views/             Home、QuickEntry、VoiceEntry（含打字）、ReceiptEntry、DraftReview（確認解析結果，
                     含 ParseProgress）、Inbox（待處理）、Transactions、Budgets、BudgetEditors、Profile、
                     Login、LedgerViews、RecurringRulesView、Components
  Assets.xcassets    App icon（沿用 co-money 的）
  UI-Mockups/        舊版的設計稿圖片，不是 v2 的設計
family_account/     另一個早期的獨立 SwiftUI 雛型（含 BACKEND_API_SPEC.md），和 v2 無關，不要拿來混用
```

**分工原則**：畫面以外的邏輯盡量放進 `MMCore` 並寫測試，`co-money/` 保持薄。

## 4. 怎麼 build 和測試

```sh
open co-money.xcodeproj            # scheme「co-money」；Team 已設定（7MJN6KPL9T）

swift test --package-path MMCore   # MMCore 的測試（應該全部通過）
```

命令列 build（這台 Mac 的 `xcode-select` 指向 Command Line Tools，要指定 `DEVELOPER_DIR`）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project co-money.xcodeproj -scheme co-money \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Alex 習慣自己開 Xcode 跑模擬器；命令列 build 和修程式可以做，裝 Xcode 元件、改系統設定交給他。

LiveTests（對 staging 跑，會建立再刪除交易、呼叫一次 LLM）：

```sh
MM_LIVE_URL=https://newsroom.codai8.com/ MM_LIVE_USER=<帳號> MM_LIVE_PASSWORD=<密碼> \
  swift test --package-path MMCore --filter Live
```

用 Alex 的帳號會在他的第一個帳本建立再刪除測試交易；最好請他在 staging 開一個測試帳號。

- Debug 預設連 staging，Release 預設連正式環境（2026-11-01 正式環境的 v2 API 上線後改回）。
  「我」頁面可以切換，兩邊的 token、待上傳、快取分開存。
- 最低 iOS 17，Swift 6 語言模式（嚴格並行檢查）。專案刻意**沒有**開
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`、`SWIFT_APPROACHABLE_CONCURRENCY`、`MEMBER_IMPORT_VISIBILITY`：
  v2 的執行緒行為是在沒有這些設定下寫的，打開會編譯失敗。

## 5. 上架前一定要做

- 確認 `co-money/AppModel.swift` 的 `Server.saved` 在 Release 是 `.production`。
- `CURRENT_PROJECT_VERSION`（build number）要比 App Store Connect 上用過的大，每次上傳都加一。
- 上傳方式：在 Mac 上 archive（Release）再用 `xcodebuild -exportArchive` 上傳到 App Store Connect，
  或在 Xcode 的 Organizer 上傳。
- 已宣告 `ITSAppUsesNonExemptEncryption = NO`（只用 HTTPS 和 Keychain）。
- Xcode Cloud 設定在 `co-money.xcodeproj/xcshareddata/xcodecloud/`。

## 6. 後端的行為（寫程式時要知道的）

- **交易的 id 由手機產生**（UUID）。`POST /api/v2/transactions/` 同一個 id 重送 → 200 回傳既有的；
  新建 → 201；id 是別人的 → 409。
- **解析工作**（§2.2）：`POST /api/v2/parse-jobs/`（multipart：`id`、`ledger_id`、`source`、`text`、
  `captured_at`、`audio`、`image`）→ 202 新建 / 200 重送 / 409。後端用 Celery 背景解析，
  `captured_at` 換成帳本時區的「今天」。狀態 QUEUED → RUNNING → DONE / FAILED → CONFIRMED / DISCARDED。
  `GET /api/v2/parse-jobs/?status=DONE,FAILED`；`POST …/{id}/confirm/`（body `{"transactions": [...]}`，
  每筆帶手機產生的 id，重送回傳同一批）；`…/discard/`；`…/retry/`。上傳的 image 必須是真的圖片。
- **登入**：`POST /api/auth/login/` → `{access, refresh}`。`POST /api/auth/login/refresh/` 每次都回傳
  **新的 refresh token**（rotation），兩張都要存；refresh token 期限 90 天；剛作廢 2 分鐘內的舊 refresh
  token 還能換（給「後端換了但手機沒收到回應」的情況）。access token 的 payload 有 `user_id`。
- **金額**一律是字串（Decimal）；時間是 ISO 8601，可能帶微秒和時區。Django 的網址結尾都有 `/`。
- **月份界線依帳本的時區**（`Ledger.timezone`），不是手機的時區。
- 外幣交易：給 `original_amount` + `original_currency`，後端用帳本匯率換算 `amount`；
  帳本沒有該幣別匯率時回 400，要使用者自己填 `amount`。
- 週期 tag 只能掛在期間內的交易上，否則 400。

## 7. 待上傳佇列（Outbox）的規則

每個寫入（建立交易、建立解析工作、確認、捨棄）都先進佇列再送，所以離線也能用：
- 成功 → 移除（建立解析工作成功後刪掉附件檔）。
- 沒網路 / 5xx → 重試，間隔 5 秒、30 秒、2 分、10 分，之後每 30 分鐘。
- 4xx → 標成「需要處理」，顯示在「待處理」讓使用者修改或捨棄；不自動重送。
- 401（refresh 也失敗）→ 停下來，全部保留，提示重新登入。
- 每筆綁定 user id，換別人登入不會送出。
- 觸發時機：新增一筆時、回到前景、網路恢復、背景 app refresh。

## 8. 現況與接下來要做的

已完成：
- `MMCore` 全部，68 個測試通過；LiveTests 對 staging 跑過（登入、交易重送、解析、確認）。
- `co-money/` 全部畫面，在 Mac 上 Xcode build 通過（模擬器與實機）；在模擬器上能啟動到登入畫面。

**接下來依序做**（細項與驗收方式看 `REQUIREMENTS.md`）：
1. **在模擬器跑一遍**：登入（staging）→ 首頁 → 記一筆 → 語音畫面的「改用打字」 → 待處理確認 → 交易列表。
   飛航模式下記一筆，恢復網路後確認自動送出。
2. **實機測錄音與語音辨識**（`VoiceRecorder`）：音檔格式、`AVAudioSession`、離線辨識。
3. **實機測拍收據**：OCR 品質、電子發票 QR。拿真的發票 QR 內容補進 `MMCore/Tests/MMCoreTests/ReceiptTests.swift`
   （目前的測試資料是照規格自己組的）。Big5 編碼的品名，`payloadStringValue` 可能是亂碼。
4. 之後：背景上傳（background `URLSession`，設計文件 §3.2）、
   語音在沒有網路且不支援離線辨識時「先存音檔、之後再辨識」（§1.1，目前只會留空讓使用者打字）。

**容易踩到的地方：**
- **Swift 6 的執行緒檢查**：在 `@MainActor` 的程式裡寫的 closure，交給會在背景執行緒呼叫它的系統 API
  （錄音 tap、語音辨識結果、`NWPathMonitor`、權限要求的 callback、`.backgroundTask`）時，會被當成只能在主執行緒跑，
  執行時直接 crash（`dispatch_assert_queue`）或編譯失敗。解法是在 `nonisolated` 的 static 方法裡產生 closure，
  或標成 `@Sendable`。`VoiceRecorder`、`Connectivity`、`MMApp.scheduleBackgroundSync` 已經這樣處理，新加的 callback 也要注意。
- **`Transaction` 和 SwiftUI 的同名型別衝突**：在 import SwiftUI 的檔案裡要寫 `MMCore.Transaction`。
- `TransactionCategory` 不能改名成 `Category`：ObjectiveC 模組已經有同名型別。
- **名稱**：畫面上一律叫「固定收支」，程式和 API 裡是 `RecurringRule` / `recurring-rules`（重複交易規則）。
  建立規則時開始日不能早於今天：後端會把開始日到今天之間的每一期都補產生交易。
- 在測試（import Testing）裡要寫 `MMCore.Tag`：Swift Testing 也有 `Tag`。
- `JSONEncoder` 把 UUID 寫成大寫；後端不分大小寫，但比較 id 時用 `UUID` 比，不要比字串。
  網址裡用 `uuid.apiString`（小寫）。
- 讀網址路徑用 `URLComponents(...).path`，`URL.path` 會去掉結尾的 `/`。
- `MMCore/.build/` 是 SwiftPM 的編譯產物，已在 `.gitignore`，不要 commit。

**和設計文件不同的兩處**（已經記在設計文件裡）：快取用 JSON 檔（`JSONCache`）不是 SwiftData；
API 型別手寫，不是 swift-openapi-generator。

## 9. 工作習慣

- Alex 習慣在功能分支上做完後「直接 merge 到 main」（fast-forward，歷史維持直線），然後刪掉已合併的分支。
  **merge 到 main 前先問 Alex。**
- commit 前先跑 `swift test --package-path MMCore`；動到 `co-money/` 的話先確認 Xcode build 得過。
- 後端的問題（API 回應不對、要加欄位）不要在 app 裡繞過，記下來告訴 Alex，在 django-mm repo 修。
