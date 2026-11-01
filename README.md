# co-money（家庭記帳 iOS，v2）

django-mm v2 API 的 iOS app，App Store 上的 co-money（`com.codai8.co-money`）。
設計文件在 django-mm repo 的 `docs/ios-design.md`，畫面草圖在 Claude 的設計畫布「家庭記帳 iOS 介面」，
要做到的事列在 `REQUIREMENTS.md`，接手開發看 `CLAUDE.md`。

## 結構

| 位置 | 內容 | 在哪裡測試 |
|---|---|---|
| `MMCore/` | Swift Package：API client、token 換發、待上傳佇列、電子發票 QR、收據文字整理、日期與快取 | Linux 或 Mac：`swift test --package-path MMCore` |
| `co-money/` | SwiftUI 畫面、錄音與語音辨識、相機與 Vision OCR、Keychain、背景同步 | 只能在 Mac 的 Xcode |
| `co-money.xcodeproj` | Xcode 專案（scheme「co-money」） | |
| `family_account/` | 早期的獨立雛型，和 v2 無關 | |

畫面以外的邏輯盡量放在 `MMCore`，因為那部分在 Linux 上也能測。

## 在 Mac 上打開

```sh
open co-money.xcodeproj
```

- Debug 連 staging（newsroom.codai8.com）。Release 原本要連正式環境（codai8.com），
  但正式環境還沒有 v2 API，**目前 Release 也連 staging，上線前不能送審**（見 `CLAUDE.md` §5）。
  「我」頁面可以切換，兩邊的登入和待上傳資料分開保存。
- 最低 iOS 17，Swift 6 語言模式。

## 測試

```sh
swift test --package-path MMCore
```

對真的後端跑（會在第一個帳本建立再刪除交易、呼叫一次 LLM 解析）：

```sh
MM_LIVE_URL=https://newsroom.codai8.com/ MM_LIVE_USER=<測試帳號> MM_LIVE_PASSWORD=<密碼> \
  swift test --package-path MMCore --filter Live
```

## 來源

v2 在 `NormalCrab/ios-mm` 的 `rewrite/v2` 分支寫成，2026-10-29 整合進這個 repo（來源 `c5cbbfd`），
取代舊的 co-money 程式碼。之後只在這個 repo 開發。

和設計文件不同的地方：

- 快取用 JSON 檔（`JSONCache`）而不是 SwiftData，為了能在 Linux 上測。資料量小，之後需要再換。
- API 的型別是手寫的（`MMCore/Sources/MMCore/Models.swift`），沒有用 swift-openapi-generator。
  對照後端的 `frontend/openapi.yml` 維護。
