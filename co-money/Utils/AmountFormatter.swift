// AmountFormatter.swift
// co-money
// 智能数字格式化：千位分隔符 + 智能小数显示
// Smart number formatting: thousand separators + smart decimal display

import Foundation

// MARK: - 金额格式化工具 | Amount Formatter

/// AmountFormatter 枚举命名空间 | AmountFormatter Enum Namespace
///
/// 在 Swift 中，枚举（enum）经常被用作"命名空间"来组织静态方法和常量。
/// 这里 AmountFormatter 不是用于创建枚举实例，而是作为一个逻辑容器来存储
/// 所有与金额格式化相关的静态方法。
/// | In Swift, enums are often used as "namespaces" to organize static methods and constants.
/// AmountFormatter here is not for creating enum instances, but as a logical container for
/// storing all static amount-formatting methods.
///
/// 为什么使用枚举作为命名空间？| Why use enum as namespace?
/// 1. 枚举不能被实例化（如果没有 case），防止意外创建对象
///    | Enums can't be instantiated (if no cases), preventing accidental object creation
/// 2. 语法清晰：AmountFormatter.format(_:) 表明这是一个"工具函数"
///    | Clear syntax: AmountFormatter.format(_:) indicates this is a "utility function"
/// 3. 比单独的全局函数更有组织性
///    | More organized than standalone global functions
enum AmountFormatter {

    /// NumberFormatter 私有静态属性 | NumberFormatter Private Static Property
    ///
    /// 数字格式化器配置 | Number Formatter Configuration
    ///
    /// NumberFormatter 是 Foundation 框架中用于格式化数字的强大工具。它处理所有
    /// 与地区设置相关的数字格式化问题（例如小数点分隔符、千位分隔符等）。
    /// | NumberFormatter is a powerful Foundation tool for formatting numbers. It handles all
    /// locale-aware number formatting (decimal separators, thousand separators, etc.).
    ///
    /// 为什么这个格式化器被声明为 private static？ | Why private static?
    /// - private: 只在这个枚举内部可访问，隐藏实现细节
    ///   | private: Only accessible within this enum, hiding implementation details
    /// - static: 属于枚举类型本身，而不是实例。整个应用程序只有一个 formatter 实例，
    ///   提高性能和内存效率
    ///   | static: Belongs to the enum type itself, not instances. Only one formatter instance
    ///   for the entire app, improving performance and memory efficiency
    ///
    /// 为什么使用闭包初始化器？ | Why use closure initializer?
    ///
    /// private static let formatter: NumberFormatter = { ... }()
    ///
    /// 这个 { ... }() 模式是"闭包初始化器"或"立即执行闭包"。
    /// | This { ... }() pattern is a "closure initializer" or "immediately-executed closure".
    ///
    /// 优点：| Benefits:
    /// 1. 可以执行多行初始化逻辑，不仅仅是单行赋值
    ///    | Can execute multi-line initialization logic, not just single assignment
    /// 2. 初始化逻辑与属性声明在一起，提高代码可读性
    ///    | Initialization logic stays with property declaration, improving readability
    /// 3. 确保属性的复杂初始化完全包含，易于理解和维护
    ///    | Ensures complex initialization is fully contained and easy to understand/maintain
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()

        /// numberStyle = .decimal | 数字格式化样式
        ///
        /// .decimal 表示使用十进制数字格式（包括可选的小数点和数字）。
        /// | .decimal indicates decimal number format (with optional decimal point and digits).
        f.numberStyle = .decimal

        /// minimumFractionDigits = 0 | 最小小数位数
        ///
        /// 从不强制显示尾部的 .00。例如：
        /// - 1234.00 会显示为 "1234" 而不是 "1234.00"
        /// | Never force trailing .00. For example:
        /// - 1234.00 displays as "1234" not "1234.00"
        f.minimumFractionDigits = 0

        /// maximumFractionDigits = 2 | 最大小数位数
        ///
        /// 允许最多 2 位小数。超过 2 位的小数会被四舍五入。例如：
        /// - 1234.5 保持为 "1234.5"（一位小数）
        /// - 1234.567 被四舍五入为 "1234.57"（两位小数）
        /// | Allow up to 2 decimal places. More than 2 decimals get rounded. For example:
        /// - 1234.5 stays "1234.5" (one decimal)
        /// - 1234.567 rounds to "1234.57" (two decimals)
        f.maximumFractionDigits = 2

        /// usesGroupingSeparator = true | 使用千位分隔符
        ///
        /// 启用千位分隔符（通常是逗号），使大数字更易读。
        /// | Enable thousand separators (usually comma) for better readability of large numbers.
        f.usesGroupingSeparator = true

        /// groupingSeparator = "," | 千位分隔符字符
        ///
        /// 显式设置分隔符为逗号 ","。不同地区可能使用不同的分隔符（例如在欧洲
        /// 可能是空格或句点），但我们这里硬编码为逗号。
        /// | Explicitly set the separator to comma ",". Different locales use different
        /// separators (e.g., space or period in Europe), but we hardcode comma here.
        f.groupingSeparator = ","

        /// groupingSize = 3 | 分组大小
        ///
        /// 每 3 位数字添加一个分隔符。例如：
        /// - 1000 → "1,000"
        /// - 1000000 → "1,000,000"
        /// | Add separator every 3 digits. For example:
        /// - 1000 → "1,000"
        /// - 1000000 → "1,000,000"
        f.groupingSize = 3

        return f
    }()

    /// 格式化绝对 Double 值 | Format Absolute Double Value
    ///
    /// - 参数 | Parameters:
    ///   - value: 要格式化的 Double 值
    ///     | The Double value to format
    ///
    /// - 返回 | Returns:
    ///   格式化后的字符串，包含千位分隔符和智能小数显示
    ///   | Formatted string with thousand separators and smart decimal display
    ///
    /// 实现细节 | Implementation Details:
    /// 1. formatter.string(from:) 使用配置好的 NumberFormatter 进行格式化
    ///    | formatter.string(from:) uses configured NumberFormatter for formatting
    /// 2. ?? 操作符提供了一个备用方案：如果格式化失败，使用 String(format:)
    ///    | ?? operator provides fallback: if formatting fails, use String(format:)
    /// 3. String(format: "%.2f", ...) 是 C 风格的格式化，确保至少有一个备选方案
    ///    | String(format: "%.2f", ...) is C-style formatting, ensures a fallback option
    static func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: abs(value)))
            ?? String(format: "%.2f", abs(value))
    }

    /// 格式化 API 返回的原始金额字符串 | Format Raw API Amount String
    ///
    /// - 参数 | Parameters:
    ///   - amountString: 来自 API 的金额字符串，例如 "1234.50"
    ///     | Amount string from API, e.g. "1234.50"
    ///
    /// - 返回 | Returns:
    ///   格式化后的字符串，例如 "1,234.5"
    ///   | Formatted string, e.g. "1,234.5"
    ///
    /// 这个重载版本提供了方便性：它接受字符串而不是 Double，自动进行转换。
    /// | This overload version provides convenience: accepts string instead of Double,
    /// automatically converts it.
    ///
    /// 示例 | Examples:
    /// - format("1234") → "1,234"
    /// - format("1234.5") → "1,234.5"
    /// - format("invalid") → "0"（转换失败时默认为 0）
    ///   | format("invalid") → "0" (defaults to 0 when conversion fails)
    static func format(_ amountString: String) -> String {
        format(Double(amountString) ?? 0)
    }

    /// 格式化金额带可选货币前缀 | Format Amount with Optional Currency Prefix
    ///
    /// - 参数 | Parameters:
    ///   - value: 要格式化的 Double 值
    ///     | The Double value to format
    ///   - currency: 可选的货币代码，例如 "TWD"、"USD" 等
    ///     | Optional currency code, e.g. "TWD", "USD", etc.
    ///
    /// - 返回 | Returns:
    ///   格式化后的字符串，包含货币代码（如果提供），例如 "TWD 1,234" 或 "USD 1,234.56"
    ///   | Formatted string with currency code (if provided), e.g. "TWD 1,234" or "USD 1,234.56"
    ///
    /// 货币处理逻辑 | Currency Handling Logic:
    /// 1. 首先使用 format(_:Double) 格式化数字部分
    ///    | First format the numeric part using format(_:Double)
    /// 2. guard let 安全解包：只有在 currency 不为 nil 且不为空字符串时才添加货币代码
    ///    | guard let safely unwraps: only add currency code if it's not nil and not empty
    /// 3. 如果没有货币代码，仅返回格式化的数字
    ///    | If no currency code, return just the formatted number
    ///
    /// 示例 | Examples:
    /// - format(1234, currency: "TWD") → "TWD 1,234"
    /// - format(1234.56, currency: "USD") → "USD 1,234.56"
    /// - format(1234, currency: nil) → "1,234"（无货币代码）
    ///   | format(1234, currency: nil) → "1,234" (no currency code)
    /// - format(1234, currency: "") → "1,234"（空字符串视为无货币）
    ///   | format(1234, currency: "") → "1,234" (empty string treated as no currency)
    static func format(_ value: Double, currency: String?) -> String {
        let num = format(value)
        guard let cur = currency, !cur.isEmpty else { return num }
        return "\(cur) \(num)"
    }

    /// 格式化 API 金额字符串带可选货币前缀 | Format API Amount String with Optional Currency
    ///
    /// - 参数 | Parameters:
    ///   - amountString: 来自 API 的金额字符串，例如 "1234.50"
    ///     | Amount string from API, e.g. "1234.50"
    ///   - currency: 可选的货币代码
    ///     | Optional currency code
    ///
    /// - 返回 | Returns:
    ///   格式化后的字符串，带货币代码，例如 "TWD 1,234.5"
    ///   | Formatted string with currency code, e.g. "TWD 1,234.5"
    ///
    /// 这是最便利的重载：接受字符串金额和货币，一步完成所有格式化。
    /// | This is the most convenient overload: accepts string amount and currency,
    /// completes all formatting in one step.
    ///
    /// 示例 | Examples:
    /// - format("1234", currency: "TWD") → "TWD 1,234"
    /// - format("1234.50", currency: "USD") → "USD 1,234.5"
    /// - format("invalid", currency: "TWD") → "TWD 0"（失败时默认为 0）
    ///   | format("invalid", currency: "TWD") → "TWD 0" (defaults to 0 on failure)
    static func format(_ amountString: String, currency: String?) -> String {
        format(Double(amountString) ?? 0, currency: currency)
    }
}
