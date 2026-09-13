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
/// - 星辰：/api/stardust/list（对象行）
/// - 鸡腿：/api/account/credit/page-N（站点 credit.js 实测：数组行 [变动, 总计, 理由, 时间]，每页 20，total 总数）
/// 请求前统一做 cookie 准备（游客态会得到 USER NOT FOUND/422）。
final class NodeSeekCreditLedgerClient {
    private let session: URLSession
    private let baseURL: URL
    private let cookiePreparer: @Sendable () async -> Void

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        cookiePreparer: @escaping @Sendable () async -> Void = {
            await NodeSeekCookieSession().prepareHTTPLoad()
        }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
    }

    private var stardustNextPage: Int?
    private var coinNextPage: Int?

    func loadLedger(kind: CreditLedgerRecord.Kind, page: Int, uid: Int) async throws -> [CreditLedgerRecord] {
        await cookiePreparer()
        switch kind {
        case .stardust:
            let loaded = try await NodeSeekStardustHTTPClient.load(page: page, uid: uid)
            stardustNextPage = loaded.nextPage
            return loaded.records
        case .coin:
            let records = try await loadCoin(page: page, uid: uid)
            coinNextPage = records.count >= 20 ? page + 1 : nil
            return records
        }
    }

    func nextPageFor(kind: CreditLedgerRecord.Kind) -> Int? {
        switch kind {
        case .stardust: return stardustNextPage
        case .coin: return coinNextPage
        }
    }

    /// 星辰明细：URLSession.shared 直连接口（登录 cookie 已在 shared storage）。
    private func loadStardust(page: Int, uid: Int) async throws -> [CreditLedgerRecord] {
        let loaded = try await NodeSeekStardustHTTPClient.load(page: page, uid: uid)
        stardustNextPage = loaded.nextPage
        return loaded.records
    }

    /// 鸡腿明细：/api/account/credit/page-N，数组行 [变动, 总计, 理由, 时间]。
    private func loadCoin(page: Int, uid: Int) async throws -> [CreditLedgerRecord] {
        let request = makeJSONRequest(
            path: "/api/account/credit/page-\(max(1, page))",
            queryItems: [],
            refererUID: uid
        )
        let root = try await fetchJSONObject(from: request)
        guard (root["success"] as? Bool) != false else {
            throw CreditLedgerClientError.unsuccessfulResponse(root["message"] as? String)
        }
        guard let arrayRows = Self.arrayRows(in: root, preferredNames: ["data", "list", "records"]) else {
            return []
        }
        return arrayRows.map { Self.ledgerRecord(fromArrayRow: $0, kind: .coin) }
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
            // 服务器用 500 包裹业务错误（如 USER NOT FOUND），取 message 更友好。
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["message"] as? String {
                throw CreditLedgerClientError.unsuccessfulResponse(message)
            }
            throw CreditLedgerClientError.httpStatus(httpResponse.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CreditLedgerClientError.unsuccessfulResponse(nil)
        }
        return object
    }
}

extension NodeSeekCreditLedgerClient {

    /// 数组行形态：data 本身是 [[Any]]。
    static func arrayRows(in root: [String: Any], preferredNames: [String]) -> [[Any]]? {
        for name in preferredNames {
            if let array = root[name] as? [[Any]] {
                return array
            }
        }
        for wrapperName in ["detail", "data"] {
            guard let wrapper = root[wrapperName] as? [String: Any] else { continue }
            for name in preferredNames {
                if let array = wrapper[name] as? [[Any]] {
                    return array
                }
            }
        }
        return nil
    }

    /// 数组行 [变动, 总计, 理由, 时间] → 记录。
    static func ledgerRecord(fromArrayRow row: [Any], kind: CreditLedgerRecord.Kind) -> CreditLedgerRecord {
        let change = Self.intValue(row.count > 0 ? row[0] : nil) ?? 0
        let balance = Self.intValue(row.count > 1 ? row[1] : nil)
        let reason = Self.stringValue(row.count > 2 ? row[2] : nil) ?? ""
        let date = Self.dateValue(row.count > 3 ? row[3] : nil)

        return CreditLedgerRecord(
            kind: kind,
            title: reason.isEmpty ? "账户变动" : reason,
            detail: nil,
            amount: abs(change),
            direction: change >= 0 ? .income : .outcome,
            balanceAfter: balance,
            date: date
        )
    }


    static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    static func dateValue(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            let seconds = number.doubleValue
            return seconds > 1_000_000_000_000
                ? Date(timeIntervalSince1970: seconds / 1000)
                : Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        let plain = DateFormatter()
        plain.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            plain.dateFormat = format
            if let date = plain.date(from: text) { return date }
        }
        return nil
    }

    static func string(in row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = Self.stringValue(row[key]), value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    static func int(in row: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = Self.intValue(row[key]) {
                return value
            }
        }
        return nil
    }

    static func date(in row: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let date = Self.dateValue(row[key]) {
                return date
            }
        }
        return nil
    }
}
