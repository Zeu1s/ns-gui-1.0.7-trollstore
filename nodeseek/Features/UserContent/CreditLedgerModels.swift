//
//  CreditLedgerModels.swift
//  nodeseek
//

import Foundation

/// 账簿流水的一条记录（鸡腿 / 星辰共用，kind 区分）。
nonisolated struct CreditLedgerRecord: Equatable, Sendable {
    enum Kind: String, Sendable {
        case coin
        case stardust
    }

    enum Direction: Sendable, Equatable {
        case income
        case outcome
        case neutral
    }

    let kind: Kind
    let title: String
    let detail: String?
    let amount: Int
    let direction: Direction
    let balanceAfter: Int?
    let date: Date?

    var amountText: String {
        let sign: String
        switch direction {
        case .income: sign = "+"
        case .outcome: sign = "-"
        case .neutral: sign = ""
        }
        return "\(sign)\(abs(amount))"
    }

    var isIncome: Bool { direction == .income }
}

extension CreditLedgerRecord.Direction {
    /// 有符号数值直接定方向；无符号按"进账默认、0 为中性"兜底。
    init(amount: Int, hasSign: Bool) {
        if hasSign {
            self = amount >= 0 ? .income : .outcome
        } else {
            self = amount == 0 ? .neutral : .income
        }
    }
}
