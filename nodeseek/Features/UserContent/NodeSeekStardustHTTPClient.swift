//
//  NodeSeekStardustHTTPClient.swift
//  nodeseek
//

import Foundation

/// 星辰明细：URLSession.shared 直接调星辰接口（会话 cookie 已由
/// NodeSeekCookieSession 同步到 HTTPCookieStorage.shared，URLSession.shared
/// 默认使用 shared storage 即自动携带登录态）。
/// 响应字段多候选容错，解析失败时把原始 body 片段记入日志便于定位。
enum NodeSeekStardustHTTPClient {
    struct Page {
        let records: [CreditLedgerRecord]
        let nextPage: Int?
    }

    static func load(page: Int, uid: Int) async throws -> Page {
        var components = URLComponents(url: NodeSeekSite.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/stardust/list"
        // 站点接口明确拒绝 page 参数（422: "page" is not allowed）。
        // 星辰明细为单页账簿，去掉多余参数。
        components?.queryItems = [URLQueryItem(name: "member_id", value: "\(uid)")]
        guard let url = components?.url else {
            throw CreditLedgerClientError.httpStatus(0)
        }

        var request = URLRequest(url: url)
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: NodeSeekSite.baseURL.appendingPathComponent("space/\(uid)"))

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        if let http = urlResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) == false {
            let snippet = String(data: data.prefix(400), encoding: .utf8) ?? ""
            AppLog.warning(.service, "星辰接口 HTTP \(http.statusCode): \(snippet)")
            // URLSession 被 Cloudflare 指纹封锁（403 拦截页）时，改用 WebView 同源 fetch。
            return try await loadViaWebView(uid)
        }

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            AppLog.warning(.service, "星辰接口非 JSON: \(String(data: data.prefix(200), encoding: .utf8) ?? "")")
            throw CreditLedgerClientError.unsuccessfulResponse("星辰接口返回格式异常")
        }
        return try parse(root: root, page: page)
    }

    /// WebView 同源 fetch 回退：绕过 URLSession 特征封锁。
    private static func loadViaWebView(_ uid: Int) async throws -> Page {
        let apiPath = "/api/stardust/list?member_id=\(uid)"
        let referer = NodeSeekSite.baseURL.appendingPathComponent("space/\(uid)")
        let response = try await WebViewJSONAPIClient.fetch(
            apiPath: apiPath,
            referer: referer
        )
        guard let statusCode = response.statusCode, (200..<300).contains(statusCode),
              let root = response.json else {
            throw CreditLedgerClientError.httpStatus(response.statusCode ?? 0)
        }
        return try parse(root: root, page: 1)
    }

    private static func parse(root: [String: Any], page: Int) throws -> Page {
        if (root["success"] as? Bool) == false {
            let message = root["message"] as? String ?? "接口失败"
            AppLog.warning(.service, "星辰接口业务失败: \(message)")
            throw CreditLedgerClientError.unsuccessfulResponse(message)
        }

        // data 兼容三种形态：顶层数组、对象行数组、包一层字典（list/records/rows/detail）。
        func rowsValue(_ value: Any?) -> Any? {
            guard let value else { return nil }
            if value is [[Any]] || value is [[String: Any]] { return value }
            if let dict = value as? [String: Any] {
                for key in ["list", "records", "rows", "detail", "data"] {
                    if let inner = dict[key], inner is [[Any]] || inner is [[String: Any]] {
                        return inner
                    }
                }
            }
            return nil
        }

        guard let rows = rowsValue(root["data"]) ?? rowsValue(root["list"]) ?? rowsValue(root["records"]) else {
            AppLog.warning(.service, "星辰接口无可识别行: \(String(data: (try? JSONSerialization.data(withJSONObject: root)) ?? Data(), encoding: .utf8)?.prefix(300) ?? "")")
            throw CreditLedgerClientError.unsuccessfulResponse("星辰接口未返回数据")
        }

        // 形态 1：数组行 [[变动, 总计, 理由, 时间], ...]
        if let arrayRows = rows as? [[Any]] {
            let records = arrayRows.map { row -> CreditLedgerRecord in
                let change = int(row.count > 0 ? row[0] : nil) ?? 0
                let balance = int(row.count > 1 ? row[1] : nil)
                let reason = string(row.count > 2 ? row[2] : nil) ?? "星辰变动"
                let date = dateValue(row.count > 3 ? row[3] : nil)
                return CreditLedgerRecord(
                    kind: .stardust,
                    title: reason,
                    detail: nil,
                    amount: abs(change),
                    direction: change >= 0 ? .income : .outcome,
                    balanceAfter: balance,
                    date: date
                )
            }
            let wrapper = root["data"] as? [String: Any]
            let total = int(root["total"]) ?? wrapper.flatMap { int($0["total"]) }
            let nextPage: Int?
            if let total {
                let maxPage = Int(ceil(Double(max(total, 1)) / 20.0))
                nextPage = page < maxPage ? page + 1 : nil
            } else {
                nextPage = records.count >= 20 ? page + 1 : nil
            }
            AppLog.info(.service, "星辰接口解析成功: rows=array, count=\(records.count), total=\(total.map(String.init) ?? "nil")")
            return Page(records: records, nextPage: nextPage)
        }

        // 形态 2：对象行 [{num, reason, ...}, ...]
        if let objectRows = rows as? [[String: Any]] {
            let records = objectRows.compactMap { row -> CreditLedgerRecord? in
                guard let amount = int(row["num"] ?? row["amount"] ?? row["change"]) else { return nil }
                let signed = row["change"] != nil
                var direction: CreditLedgerRecord.Direction = .neutral
                if let type = string(row["type"] ?? row["direction"]) {
                    let lowered = type.lowercased()
                    if lowered.contains("out") || lowered.contains("sub") || lowered.contains("pay") || lowered.contains("send") || lowered.contains("use") {
                        direction = .outcome
                    } else if lowered.contains("in") || lowered.contains("add") || lowered.contains("recv") {
                        direction = .income
                    }
                }
                if direction == .neutral {
                    direction = CreditLedgerRecord.Direction(amount: amount, hasSign: signed)
                }
                return CreditLedgerRecord(
                    kind: .stardust,
                    title: string(row["reason"] ?? row["title"] ?? row["remark"]) ?? "星辰变动",
                    detail: string(row["detail"] ?? row["from_name"] ?? row["member_name"] ?? row["desc"]),
                    amount: abs(amount),
                    direction: direction,
                    balanceAfter: int(row["balance"] ?? row["total"] ?? row["remain"]),
                    date: dateValue(row["created_at"] ?? row["time"] ?? row["date"])
                )
            }
            if records.isEmpty == false {
                AppLog.info(.service, "星辰接口解析成功: rows=object, count=\(records.count)")
                return Page(records: records, nextPage: records.count >= 20 ? page + 1 : nil)
            }
            // 对象行但都解析不出金额：记日志暴露真实字段
            AppLog.warning(.service, "星辰对象行解析失败: \(String(data: (try? JSONSerialization.data(withJSONObject: root)) ?? Data(), encoding: .utf8)?.prefix(400) ?? "")")
        }

        throw CreditLedgerClientError.unsuccessfulResponse("星辰明细数据形态未知")
    }

    private static func int(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String, s.isEmpty == false { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let n = value as? NSNumber {
            let seconds = n.doubleValue
            return seconds > 1_000_000_000_000
                ? Date(timeIntervalSince1970: seconds / 1000)
                : Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: text) { return d }
        let plain = DateFormatter()
        plain.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            plain.dateFormat = format
            if let d = plain.date(from: text) { return d }
        }
        return nil
    }
}
