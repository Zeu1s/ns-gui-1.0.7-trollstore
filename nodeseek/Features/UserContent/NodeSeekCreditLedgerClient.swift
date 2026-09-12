//
//  NodeSeekCreditLedgerClient.swift
//  nodeseek
//

import Foundation

enum CreditLedgerClientError: LocalizedError {
    case httpStatus(Int)
    case unsuccessfulResponse(String?)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "服务器返回 \(code)"
        case .unsuccessfulResponse(let message):
            return message ?? "接口返回失败"
        }
    }
}

/// 星辰/鸡腿账簿客户端。
/// 首选 JSON 接口（星辰 list 已确认存在）；响应字段名以多候选容错解析，
/// 避免线上字段名与推测不一致导致整页失败。
final class NodeSeekCreditLedgerClient {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func loadLedger(kind: CreditLedgerRecord.Kind, page: Int, uid: Int) async throws -> [CreditLedgerRecord] {
        switch kind {
        case .stardust:
            return try await loadStardust(page: page, uid: uid)
        case .coin:
            return try await loadCoin(page: page, uid: uid)
        }
    }

    /// 星辰明细：/api/stardust/list（member_id + page，已确认端点存在）。
    private func loadStardust(page: Int, uid: Int) async throws -> [CreditLedgerRecord] {
        let request = makeJSONRequest(
            path: "/api/stardust/list",
            queryItems: [
                URLQueryItem(name: "member_id", value: "\(uid)"),
                URLQueryItem(name: "page", value: "\(max(1, page))")
            ],
            refererUID: uid
        )
        let root = try await fetchJSONObject(from: request)
        guard (root["success"] as? Bool) != false else {
            throw CreditLedgerClientError.unsuccessfulResponse(root["message"] as? String)
        }
        let rows = Self.rows(in: root, preferredNames: ["list", "records", "data", "items", "detail"])
        return rows.compactMap { Self.stardustRecord(from: $0) }
    }

    /// 鸡腿明细：未发现稳定 JSON 端点，走账簿 HTML 页解析（App 带 cookie 的 HTTP 客户端）。
    private func loadCoin(page: Int, uid: Int) async throws -> [CreditLedgerRecord] {
        let client = HTTPHTMLClient()
        var components = URLComponents(url: baseURL.appendingPathComponent("credit"), resolvingAgainstBaseURL: false)
        if page > 1 {
            // 网页账簿分页形如 /credit#/p-2；服务端渲染版用 query 兜底，两态都能解析。
            components?.queryItems = [URLQueryItem(name: "page", value: "\(page)")]
        }
        guard let url = components?.url else {
            throw CreditLedgerClientError.httpStatus(0)
        }
        let response = try await client.get(url)
        guard (200..<300).contains(response.statusCode) else {
            throw CreditLedgerClientError.httpStatus(response.statusCode)
        }
        return CreditLedgerHTMLParser.parse(html: response.html, kind: .coin)
    }

    private func makeJSONRequest(path: String, queryItems: [URLQueryItem], refererUID: Int) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems
        let url = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        let referer = baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(refererUID)")
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: referer)
        return request
    }

    private func fetchJSONObject(from request: URLRequest) async throws -> [String: Any] {
        let (data, urlResponse) = try await session.data(for: request)
        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw CreditLedgerClientError.httpStatus(httpResponse.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CreditLedgerClientError.unsuccessfulResponse(nil)
        }
        return object
    }
}

extension NodeSeekCreditLedgerClient {
    /// 星辰行 → 记录。字段名按可能的写法多候选容错。
    static func stardustRecord(from row: [String: Any]) -> CreditLedgerRecord? {
        let title = Self.string(in: row, keys: ["title", "name", "reason", "description", "remark", "memo", "content"])
            ?? "星辰变动"
        let detail = Self.string(in: row, keys: ["detail", "desc", "note", "from_name", "target_name", "member_name"])
        let amount = Self.int(in: row, keys: ["num", "amount", "value", "change", "stardust", "count"]) ?? 0
        let signed = Self.int(in: row, keys: ["change", "delta", "offset"]) != nil
        let balance = Self.int(in: row, keys: ["balance", "after", "remain", "total"])
        let date = Self.date(in: row, keys: ["created_at", "createdAt", "time", "date", "created_time"])

        var direction: CreditLedgerRecord.Direction = .neutral
        if let typeText = Self.string(in: row, keys: ["type", "direction", "action"]) {
            let lowered = typeText.lowercased()
            if lowered.contains("in") || lowered.contains("add") || lowered.contains("income") || lowered.contains("recv") {
                direction = .income
            } else if lowered.contains("out") || lowered.contains("sub") || lowered.contains("pay") || lowered.contains("send") || lowered.contains("use") {
                direction = .outcome
            }
        }
        if direction == .neutral, signed {
            direction = amount >= 0 ? .income : .outcome
        }
        return CreditLedgerRecord(
            kind: .stardust,
            title: title,
            detail: detail,
            amount: abs(amount),
            direction: direction,
            balanceAfter: balance,
            date: date
        )
    }

    static func string(in row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = row[key] as? String, value.isEmpty == false {
                return value
            }
            if let number = row[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    static func int(in row: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let number = row[key] as? NSNumber {
                return number.intValue
            }
            if let text = row[key] as? String, let value = Int(text) {
                return value
            }
        }
        return nil
    }

    static func date(in row: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let interval = row[key] as? NSNumber {
                let seconds = interval.doubleValue
                return seconds > 1_000_000_000_000
                    ? Date(timeIntervalSince1970: seconds / 1000)
                    : Date(timeIntervalSince1970: seconds)
            }
            if let text = row[key] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: text) {
                    return date
                }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: text) {
                    return date
                }
                let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
                let plain = DateFormatter()
                plain.timeZone = TimeZone.current
                for format in formats {
                    plain.dateFormat = format
                    if let date = plain.date(from: text) {
                        return date
                    }
                }
            }
        }
        return nil
    }

    static func rows(in root: [String: Any], preferredNames: [String]) -> [[String: Any]] {
        for name in preferredNames {
            if let array = root[name] as? [[String: Any]] {
                return array
            }
        }
        // 兜底：嵌套在 detail/data 里再找一层
        for wrapperName in ["detail", "data"] {
            guard let wrapper = root[wrapperName] as? [String: Any] else { continue }
            for name in preferredNames {
                if let array = wrapper[name] as? [[String: Any]] {
                    return array
                }
            }
        }
        return []
    }
}
