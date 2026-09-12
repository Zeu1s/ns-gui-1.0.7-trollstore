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
        return rows.compactMap { Self.record(from: $0, kind: .stardust) }
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
