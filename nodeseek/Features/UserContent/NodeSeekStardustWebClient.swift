//
//  NodeSeekStardustWebClient.swift
//  nodeseek
//

import Foundation

/// 星辰明细：通过隐藏 WebView 在登录态页面里直接 fetch 星辰接口。
/// 直接 HTTP 会因缺会话/参数校验失败（page is not allowed / USER NOT FOUND），
/// 页面内 fetch 自带完整 cookie 与站点预期参数。
enum NodeSeekStardustWebClient {

    struct Page {
        let records: [CreditLedgerRecord]
        let nextPage: Int?
    }

    static func load(page: Int, uid: Int) async throws -> Page {
        let pageURL = NodeSeekSite.baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(uid)")
        let script = """
        return await new Promise(async (resolve) => {
          try {
            const response = await fetch('/api/stardust/list?member_id=' + memberID + '&page=' + String(page), {
              credentials: 'same-origin',
              headers: { 'Accept': 'application/json' }
            });
            const body = await response.json().catch(() => ({}));
            resolve({
              ok: response.status >= 200 && response.status < 300 && body.success !== false,
              statusCode: response.status,
              message: body.message || body.msg || null,
              data: body.data || null,
              total: body.total || null
            });
          } catch (error) {
            resolve({ ok: false, message: String(error && error.message ? error.message : error) });
          }
        });
        """

        let result = try await withHiddenWebViewPageActionLoader(
            logMessage: "准备通过登录态页面读取星辰明细: page=\(page)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: pageURL,
                source: script,
                arguments: [
                    "memberID": uid,
                    "page": max(1, page)
                ],
                timeoutInterval: 20,
                actionName: "读取星辰明细"
            )
        }

        guard result["ok"] as? Bool == true else {
            throw CreditLedgerClientError.unsuccessfulResponse(
                result["message"] as? String ?? "星辰明细接口返回失败"
            )
        }

        // data 形态 1：[[变动, 总计, 理由, 时间], ...]（与鸡腿账簿同构）
        if let arrayRows = result["data"] as? [[Any]] {
            let records = arrayRows.map { row in
                let change = Self.intValue(row.count > 0 ? row[0] : nil) ?? 0
                let balance = Self.intValue(row.count > 1 ? row[1] : nil)
                let reason = Self.stringValue(row.count > 2 ? row[2] : nil) ?? "星辰变动"
                let date = Self.dateValue(row.count > 3 ? row[3] : nil)
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
            let total = Self.intValue(result["total"])
            let nextPage = total.map { total -> Int? in
                let maxPage = Int(ceil(Double(max(total, 1)) / 20.0))
                return page < maxPage ? page + 1 : nil
            }
            return Page(records: records, nextPage: page < (nextPage.map { $0 } ?? page + 1) ? page + 1 : nil)
        }

        // data 形态 2：对象行 [{num, reason, created_at, ...}, ...]
        if let objectRows = result["data"] as? [[String: Any]] {
            let records = objectRows.compactMap { row -> CreditLedgerRecord? in
                guard let amount = Self.intValue(row["num"] ?? row["amount"] ?? row["change"]) else { return nil }
                let signed = row["change"] != nil
                let direction: CreditLedgerRecord.Direction
                if let type = Self.stringValue(row["type"] ?? row["direction"]) {
                    let lowered = type.lowercased()
                    if lowered.contains("out") || lowered.contains("sub") || lowered.contains("pay") || lowered.contains("send") {
                        direction = .outcome
                    } else {
                        direction = .income
                    }
                } else {
                    direction = CreditLedgerRecord.Direction(amount: amount, hasSign: signed)
                }
                return CreditLedgerRecord(
                    kind: .stardust,
                    title: Self.stringValue(row["reason"] ?? row["title"] ?? row["remark"]) ?? "星辰变动",
                    detail: Self.stringValue(row["detail"] ?? row["from_name"] ?? row["member_name"]),
                    amount: abs(amount),
                    direction: direction,
                    balanceAfter: Self.intValue(row["balance"] ?? row["total"] ?? row["remain"]),
                    date: Self.dateValue(row["created_at"] ?? row["time"] ?? row["date"])
                )
            }
            return Page(records: records, nextPage: records.count >= 20 ? page + 1 : nil)
        }

        throw CreditLedgerClientError.unsuccessfulResponse("星辰明细数据形态未知")
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
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
