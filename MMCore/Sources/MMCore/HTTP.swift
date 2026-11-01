import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Sendable, Hashable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Hashable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

/// 實際把請求送出去的那一層。測試換成假的，app 用 `URLSessionTransport`。
public protocol HTTPTransport: Sendable {
    /// 網路層的失敗（沒網路、逾時）丟出錯誤；有收到回應就回傳，不管狀態碼。
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 30
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }
}

/// API 呼叫失敗的分類。分類決定了待上傳的項目要怎麼處理（ios-design §4.3）。
public enum APIError: Error, Hashable, Sendable {
    /// 沒有網路、逾時、DNS 失敗：之後再試。
    case offline(String)
    /// 登入失效（refresh token 也被拒絕）：要重新登入，待上傳的資料保留。
    case unauthorized
    /// 4xx：資料本身有問題，重送也沒用，要使用者處理。
    case client(status: Int, message: String, fieldErrors: [String: [String]])
    /// 5xx：伺服器的問題，之後再試。
    case server(status: Int)
    /// 回應的格式和預期的不一樣。
    case decoding(String)

    /// 這個錯誤之後重試有沒有機會成功。
    public var isRetryable: Bool {
        switch self {
        case .offline, .server: true
        case .unauthorized, .client, .decoding: false
        }
    }

    /// 給使用者看的訊息。
    public var message: String {
        switch self {
        case .offline: "沒有網路，連線後會自動送出"
        case .unauthorized: "登入已過期，請重新登入"
        case .client(_, let message, _): message
        case .server: "伺服器暫時有問題，稍後會自動重試"
        case .decoding: "伺服器的回應格式不對，請更新 app"
        }
    }

    /// 依狀態碼和回應內容分類。
    static func from(status: Int, body: Data) -> APIError {
        switch status {
        case 401: return .unauthorized
        case 400..<500:
            let (message, fields) = ErrorBody.parse(body)
            return .client(status: status, message: message ?? defaultMessage(status), fieldErrors: fields)
        default: return .server(status: status)
        }
    }

    private static func defaultMessage(_ status: Int) -> String {
        switch status {
        case 403: "沒有權限（可能已經被移出這個帳本）"
        case 404: "找不到這筆資料，可能已經被刪除"
        case 409: "資料衝突，請重新整理"
        default: "資料有誤（\(status)）"
        }
    }
}

/// DRF 的錯誤回應有好幾種形狀：
/// `{"detail": "..."}`、`{"欄位": ["訊息"]}`、`{"non_field_errors": [...]}`、巢狀的清單。
/// 全部攤平成一句話給使用者看，並保留欄位對應給表單用。
enum ErrorBody {
    static func parse(_ body: Data) -> (message: String?, fields: [String: [String]]) {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return (nil, [:])
        }
        var fields: [String: [String]] = [:]
        if let object = json as? [String: Any] {
            if let detail = object["detail"] as? String {
                return (detail, [:])
            }
            for (key, value) in object {
                let messages = strings(in: value)
                if !messages.isEmpty { fields[key] = messages }
            }
        }
        let all = fields.keys.sorted { a, b in
            // 不屬於特定欄位的錯誤放前面，其餘照欄位名排，讓訊息順序固定。
            (a == "non_field_errors" ? 0 : 1, a) < (b == "non_field_errors" ? 0 : 1, b)
        }.flatMap { fields[$0]! }
        let message = all.isEmpty ? strings(in: json).first : all.joined(separator: "；")
        return (message, fields)
    }

    private static func strings(in value: Any) -> [String] {
        switch value {
        case let text as String: [text]
        case let list as [Any]: list.flatMap(strings(in:))
        case let object as [String: Any]: object.keys.sorted().flatMap { strings(in: object[$0]!) }
        default: []
        }
    }
}

/// multipart/form-data 的內容（建立解析工作時附音檔 / 圖片）。
public struct MultipartForm: Sendable {
    public let boundary: String
    private var parts: [Data] = []

    public init(boundary: String = "mm-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public mutating func add(_ name: String, _ value: String) {
        var part = Data()
        part.append("--\(boundary)\r\n")
        part.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        part.append(value)
        part.append("\r\n")
        parts.append(part)
    }

    public mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        var part = Data()
        part.append("--\(boundary)\r\n")
        part.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        part.append("Content-Type: \(mimeType)\r\n\r\n")
        part.append(data)
        part.append("\r\n")
        parts.append(part)
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public var body: Data {
        var data = parts.reduce(into: Data()) { $0.append($1) }
        data.append("--\(boundary)--\r\n")
        return data
    }
}

extension Data {
    mutating func append(_ text: String) {
        append(Data(text.utf8))
    }
}
