//
//  CreditLedgerHTMLParser.swift
//  nodeseek
//

import Foundation
import Kanna

/// 账簿 HTML 页的容错解析：表格行 / 列表项两种形态都尝试，
/// 字段名按线上可能出现的写法多候选匹配。
enum CreditLedgerHTMLParser {
    static func parse(html: String, kind: CreditLedgerRecord.Kind) -> [CreditLedgerRecord] {
        guard let document = try? Kanna.HTML(html: html, encoding: .utf8) else {
            return []
        }

        var records: [CreditLedgerRecord] = []

        // 形态一：<table> 内 tr 行
        let rows = document.xpath("//table//tr[td]")
        for row in rows {
            let cells = row.xpath("td").compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cells.count >= 2 else { continue }
            records.append(record(fromCells: cells, kind: kind))
        }

        if records.isEmpty {
            // 形态二：ul/li 或 div 列表项（每项含标题+时间+数值）
            let items = document.xpath("//ul/li | //div[contains(@class,'item')]")
            for item in items {
                let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count > 5 else { continue }
                let amount = Self.amount(in: text)
                let date = Self.date(in: text)
                guard amount != 0 || date != nil else { continue }
                records.append(CreditLedgerRecord(
                    kind: kind,
                    title: String(text.prefix(60)),
                    detail: nil,
                    amount: abs(amount),
                    direction: CreditLedgerRecord.Direction(
                        amount: amount,
                        hasSign: text.contains("+") || text.contains("-")
                    ),
                    balanceAfter: nil,
                    date: date
                ))
            }
        }

        return records
    }

    /// 表格单元格 → 记录。约定列序：标题/来源、数值、余额（可选）、时间（位置不定，按内容识别）。
    private static func record(fromCells cells: [String], kind: CreditLedgerRecord.Kind) -> CreditLedgerRecord {
        var title: String?
        var amountText: String?
        var balance: Int?
        var date: Date?

        for cell in cells {
            if date == nil, let parsedDate = Self.date(in: cell) {
                date = parsedDate
                continue
            }
            if Self.isAmount(cell) {
                if amountText == nil {
                    amountText = cell
                } else if balance == nil {
                    balance = Self.amount(in: cell)
                }
                continue
            }
            if title == nil, cell.count >= 2 {
                title = cell
            }
        }

        let amount = Self.amount(in: amountText ?? "")
        return CreditLedgerRecord(
            kind: kind,
            title: title ?? cells.first ?? "",
            detail: nil,
            amount: abs(amount),
            direction: CreditLedgerRecord.Direction(
                amount: amount,
                hasSign: (amountText ?? "").contains("+") || (amountText ?? "").contains("-")
            ),
            balanceAfter: balance,
            date: date
        )
    }

    private static func isAmount(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= 12 else { return false }
        let body = trimmed
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
        return !body.isEmpty && body.allSatisfy { $0.isNumber }
    }

    private static func amount(in text: String) -> Int {
        let negative = text.contains("-")
        let digits = text.compactMap { $0.isNumber ? $0 : nil }
        guard let value = Int(String(digits)) else { return 0 }
        return negative ? -value : value
    }

    private static func date(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.date
    }
}
