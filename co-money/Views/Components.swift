import MMCore
import SwiftUI

/// 設計畫布上的顏色。
enum Palette {
    static let accent = Color(hex: 0xF34C27)
    static let accentSoft = Color(hex: 0xFFECE7)
    static let accentText = Color(hex: 0xAA1E02)
    static let teal = Color(hex: 0x1EA0B4)
    static let income = Color(hex: 0x00606D)
    static let warning = Color(hex: 0xC22908)
    static let divider = Color(hex: 0xF0EBE5)
    static let border = Color(hex: 0xE8E1D9)
    static let secondaryText = Color(hex: 0x7A736B)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension TransactionCategory {
    /// SF Symbols 的圖示。
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .clothing: "tshirt"
        case .housing: "house"
        case .transport: "car"
        case .education: "graduationcap"
        case .entertainment: "gamecontroller"
        case .medical: "cross.case"
        case .other: "ellipsis"
        }
    }

    var tint: (background: Color, foreground: Color) {
        switch self {
        case .food: (Color(hex: 0xFFECE7), Color(hex: 0xC22908))
        case .transport: (Color(hex: 0xE5FAFD), Color(hex: 0x007C8D))
        case .housing: (Color(hex: 0xFFF3D6), Color(hex: 0x7A5200))
        case .entertainment: (Color(hex: 0xEFE9FB), Color(hex: 0x5B3FA6))
        default: (Color(hex: 0xF1EFEC), Color(hex: 0x5C5751))
        }
    }
}

struct CategoryIcon: View {
    let category: TransactionCategory

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(category.tint.foreground)
            .frame(width: 36, height: 36)
            .background(category.tint.background, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 頂部的細橫幅：離線時「離線中・資料更新於 10:42」（§4.5）；
/// 連得上但讀取失敗（例如伺服器 5xx）時顯示原因，提醒畫面上不是最新的資料。
struct OfflineBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isOffline {
            banner(symbol: "wifi.slash", text: text, color: Color(hex: 0x5C5751))
        } else if let error = model.loadError {
            banner(symbol: "exclamationmark.triangle", text: error, color: Palette.warning)
        }
    }

    private func banner(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color)
    }

    private var text: String {
        guard let updatedAt = model.updatedAt else { return "離線中" }
        return "離線中・資料更新於 \(DateText.time(updatedAt, in: model.timeZone))"
    }
}

/// 預算進度條。超過 90% 變紅。
struct BudgetBar: View {
    let tag: Tag

    var body: some View {
        let progress = min(tag.progress ?? 0, 1)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.divider)
                Capsule().fill(color).frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 6)
    }

    private var color: Color { (tag.progress ?? 0) >= 0.9 ? Palette.accent : Palette.teal }
}

/// 常用的幣別。帳本沒設定某個幣別的匯率時，後端會拒絕外幣交易。
enum Currencies {
    static let common = ["TWD", "JPY", "USD", "EUR", "KRW", "HKD", "CNY", "THB"]

    /// 帳本幣別和匯率設定可以選的幣別。
    static let all = common + ["GBP", "AUD", "CAD", "NZD", "SGD", "MYR", "VND", "PHP", "IDR", "CHF"]

    /// 帳本的幣別排第一個，其他常用的接在後面。
    static func options(base: String) -> [String] {
        [base] + common.filter { $0 != base }
    }
}

/// 月份選單：首頁、交易、預算共用同一個月份，在任何一頁換了，其他頁也跟著換。
struct MonthMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.monthOptions, id: \.self) { option in
                Button {
                    Task { await model.changeMonth(to: option) }
                } label: {
                    if option == model.month {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.month.label)
                Image(systemName: "chevron.down").font(.caption)
            }
        }
    }
}

/// 帳本切換：首頁標題旁邊的選單。
struct LedgerMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.ledgers.count > 1 {
            menu
        } else {
            // 只有一個帳本時不用切換，只顯示名稱。
            Text(model.selectedLedger?.name ?? "帳本").font(.headline)
        }
    }

    private var menu: some View {
        Menu {
            ForEach(model.ledgers) { ledger in
                Button {
                    Task { await model.selectLedger(ledger.id) }
                } label: {
                    if ledger.id == model.selectedLedger?.id {
                        Label(ledger.name, systemImage: "checkmark")
                    } else {
                        Text(ledger.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.selectedLedger?.name ?? "帳本").font(.headline)
                Image(systemName: "chevron.down").font(.caption)
            }
            .foregroundStyle(.primary)
        }
    }
}

extension Money {
    /// 從數字鍵盤輸入的文字建立。小數點跟著地區設定（有些地區是逗號）；
    /// `Money(string:)` 會把逗號當千分位，不先換掉的話 "12,5" 會變成 125。
    init?(userInput text: String) {
        let normalized = Locale.current.decimalSeparator == ","
            ? text.replacingOccurrences(of: ",", with: ".") : text
        self.init(string: normalized)
    }

    /// 支出顯示為正數、收入加負號（和網頁一致：金額代表「花掉」多少）。
    func signed(for type: TransactionType) -> String {
        type == .income ? "−" + display : display
    }
}

extension View {
    /// 卡片樣式：白底、圓角、細框。
    func card() -> some View {
        padding(16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }
}
