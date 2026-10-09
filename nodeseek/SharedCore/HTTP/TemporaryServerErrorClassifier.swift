//
//  TemporaryServerErrorClassifier.swift
//  nodeseek
//

import Foundation

/// 站点"稍后重试即可"错误的统一判定。
///
/// 这里只收编语义完全一致的那一类：503 / service unavailable。通知页和资料页
/// 原先各写了一份逐字相同的实现，合并到此处避免继续分叉。
///
/// 注意本类型**不**包含 429 与 Cloudflare 挑战：那是"你已经超线了"，
/// 自动重试只会给限流窗口续命。需要那套语义的调用方（如详情页重试、
/// 列表页临时失败重试）有自己的判定，不要改到这里来。
enum TemporaryServerErrorClassifier {
    /// 服务端明确返回"暂时不可用"。
    nonisolated static func isServiceUnavailable(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("503") || message.contains("service unavailable")
    }
}
