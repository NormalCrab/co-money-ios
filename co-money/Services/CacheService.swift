// CacheService.swift
// co-money
// Local JSON file cache for offline support.
// Saves fetched data to app's Documents directory so it persists across launches.

import Foundation

// MARK: - CacheService Overview
// 缓存服务 - 本地JSON文件缓存系统
//
// 这个类提供离线支持，将API获取的数据保存为JSON文件到应用的Documents目录。
// 这样用户可以在离线时继续查看之前加载过的数据。
//
// This service provides offline support by caching API responses as JSON files
// in the app's Documents directory. Users can view previously loaded data even
// when offline. The cache persists across app restarts and logouts.
//
// Design Pattern: Singleton
// 单例模式 - 确保全应用只有一个缓存实例
// Ensures all code accesses the same cache directory and instances.
//
// Key Swift Concepts Used:
// 1. Generics<T: Encodable> and <T: Decodable>
//    泛型 - 允许保存和加载任何遵循Encodable/Decodable协议的类型
//    Allows saving/loading any type that conforms to Encodable/Decodable protocols
//
// 2. Protocol-Oriented Design
//    Encodable/Decodable是Swift协议，让我们的数据类型自动支持JSON序列化
//    Using Swift's Codable protocol for type-safe JSON encoding/decoding
//
// 3. Lazy Initialization (encoder/decoder)
//    延迟初始化 - encoder和decoder在第一次访问时才创建
//    The encoder and decoder are only created once and reused

final class CacheService {
    // Singleton instance
    // 单例实例 - 全应用共享的唯一缓存服务
    // Shared instance used throughout the app
    static let shared = CacheService()

    // Private initializer
    // 私有初始化器 - 强制使用singleton
    // Prevents creating multiple cache service instances
    private init() {
        // Ensure cache directory exists when service is first created
        // 当服务首次创建时，确保缓存目录存在
        // Creates the directory with intermediate directories if needed
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Cache Directory Management
    // 缓存目录管理 - 计算属性，动态获取缓存目录路径

    /// The directory where all cache files are stored
    /// 所有缓存文件存储的目录
    ///
    /// FileManager locations:
    /// - .documentDirectory: 应用数据目录，用户可访问，iOS会备份
    /// - .userDomainMask: 在该用户的主目录中查找
    ///
    /// Returns a URL like: /Users/xxx/Documents/co-money-cache/
    private var cacheDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("co-money-cache", isDirectory: true)
    }

    // MARK: - JSON Encoder Setup
    // JSON编码器设置 - 配置如何将Swift对象编码为JSON

    /// Lazy-initialized JSONEncoder with ISO8601 date strategy
    /// 延迟初始化的JSONEncoder，使用ISO8601日期格式
    ///
    /// Why lazy initialization?
    /// 为什么延迟初始化？
    /// - Avoid creating multiple encoder instances
    ///   避免创建多个编码器实例
    /// - Encoder is CPU-heavy, reusing it is more efficient
    ///   编码器CPU密集，重用它更高效
    /// - Only created once when first accessed
    ///   仅在首次访问时创建一次
    ///
    /// dateEncodingStrategy: 日期编码策略
    /// - .iso8601: 将Date编码为ISO 8601格式字符串 (如 "2024-01-15T10:30:00Z")
    /// - Allows other devices/languages to read our cached JSON
    ///   允许其他设备/语言读取我们的缓存JSON
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - JSON Decoder Setup
    // JSON解码器设置 - 配置如何将JSON解析为Swift对象

    /// Lazy-initialized JSONDecoder with flexible date parsing strategy
    /// 延迟初始化的JSONDecoder，使用灵活的日期解析策略
    ///
    /// Custom date decoding strategy:
    /// 自定义日期解码策略：
    /// Tries multiple ISO8601 date formats because different systems format dates differently:
    /// 尝试多种ISO8601日期格式，因为不同系统的日期格式不同：
    /// - withFractionalSeconds: 包含毫秒的完整格式 (如 "2024-01-15T10:30:00.123Z")
    /// - Basic format: 基本格式 (如 "2024-01-15T10:30:00Z")
    ///
    /// This approach makes our decoder robust to date format variations from the backend
    /// 这种方法使解码器能够处理来自后端的各种日期格式变化
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Custom date decoding: try multiple formats
        // 自定义日期解码：尝试多种格式
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            // Try full format with fractional seconds first
            // 先尝试包含毫秒的完整格式
            let isoFull = ISO8601DateFormatter()
            isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFull.date(from: str) { return date }

            // Try basic ISO8601 format
            // 尝试基本ISO8601格式
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: str) { return date }

            // If both fail, throw a descriptive error
            // 如果两个都失败，抛出描述性错误
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return d
    }()

    // MARK: - Generic Save / Load
    // 泛型保存/加载 - 使用泛型实现类型安全的缓存
    // 这是Swift Generics的强大示例

    /// Save any Encodable value to cache as JSON file
    /// 将任何Encodable值保存到缓存为JSON文件
    ///
    /// Generic Parameter <T: Encodable>:
    /// 泛型参数 <T: Encodable>:
    /// - T is a placeholder for any type that conforms to Encodable protocol
    ///   T是任何遵循Encodable协议的类型的占位符
    /// - Compiler ensures type safety: can't pass non-Encodable types
    ///   编译器确保类型安全：不能传递不可编码的类型
    ///
    /// Example usage:
    /// CacheService.shared.save(myTransactions, key: "transactions")
    /// // myTransactions must have Codable conformance (automatic for most data types)
    /// // myTransactions必须遵循Codable协议（大多数数据类型自动遵循）
    ///
    /// Implementation details:
    /// 实现细节：
    /// - try?: 如果编码或写入失败，静默失败（不抛出异常）
    ///   Silent failure: if encoding fails, just return without saving
    /// - .atomic: 原子写入 - 要么完全写入，要么不写入（避免部分写入）
    ///   Atomic write: either fully writes or doesn't write (no partial files)
    func save<T: Encodable>(_ value: T, key: String) {
        // Construct file path: e.g., "/Documents/co-money-cache/transactions.json"
        // 构造文件路径：例如"/Documents/co-money-cache/transactions.json"
        let url = cacheDir.appendingPathComponent("\(key).json")

        // Encode the value to JSON Data
        // 将值编码为JSON Data
        if let data = try? encoder.encode(value) {
            // Write data to file atomically
            // 原子方式将数据写入文件
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Load any Decodable value from cache
    /// 从缓存加载任何Decodable值
    ///
    /// Generic Parameter <T: Decodable>:
    /// 泛型参数 <T: Decodable>:
    /// - T is a placeholder for the return type
    ///   T是返回类型的占位符
    /// - Compiler ensures you're loading the correct type
    ///   编译器确保加载正确的类型
    ///
    /// Example usage:
    /// if let transactions = CacheService.shared.load([Transaction].self, key: "transactions") {
    ///     // transactions is guaranteed to be [Transaction] type
    ///     // transactions保证是[Transaction]类型
    /// }
    ///
    /// Returns nil if:
    /// 返回nil如果：
    /// - File doesn't exist
    ///   文件不存在
    /// - Data is corrupted or invalid JSON
    ///   数据损坏或JSON无效
    /// - Decoding fails (data doesn't match expected type structure)
    ///   解码失败（数据与预期类型结构不匹配）
    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        // Construct file path
        // 构造文件路径
        let url = cacheDir.appendingPathComponent("\(key).json")

        // Try to read file data
        // 尝试读取文件数据
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Try to decode JSON to the requested type
        // 尝试将JSON解码为请求的类型
        return try? decoder.decode(type, from: data)
    }

    // MARK: - Cache Keys (Constants)
    // 缓存键常量 - 定义应用中所有缓存的键名
    // Using static let constants ensures consistency and prevents typos
    // 使用static let常量确保一致性并防止打字错误

    /// Cache key for shared transactions (group or team transactions)
    /// 共享交易缓存键（小组或团队交易）
    static let transactionsKey = "transactions"

    /// Cache key for personal transactions
    /// 个人交易缓存键
    static let personalTransactionsKey = "personalTransactions"

    /// Cache key for transaction categories
    /// 交易类别缓存键
    static let categoriesKey = "categories"

    /// Cache key for accounts
    /// 账户缓存键
    static let accountsKey = "accounts"

    /// Cache key for user profile
    /// 用户资料缓存键
    static let profileKey = "profile"

    /// Cache key for current month statistics (shared transactions)
    /// 当月统计缓存键（共享交易）
    static let currentMonthKey = "currentMonth"

    /// Cache key for personal current month statistics
    /// 个人当月统计缓存键
    static let personalCurrentMonthKey = "personalCurrentMonth"

    // MARK: - Clear All Cache
    // 清空所有缓存 - 在注销或重置应用时使用

    /// Remove all cached files and recreate the cache directory
    /// 删除所有缓存文件并重新创建缓存目录
    ///
    /// Used when:
    /// 用于以下情况：
    /// - User logs out and wants to clear all data
    ///   用户注销并希望清除所有数据
    /// - User wants to reset the app
    ///   用户希望重置应用
    /// - Server data has been updated and we need fresh data
    ///   服务器数据已更新，需要新数据
    func clearAll() {
        // Remove the entire cache directory
        // 删除整个缓存目录
        try? FileManager.default.removeItem(at: cacheDir)

        // Recreate empty cache directory for next use
        // 为下一次使用重新创建空缓存目录
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
