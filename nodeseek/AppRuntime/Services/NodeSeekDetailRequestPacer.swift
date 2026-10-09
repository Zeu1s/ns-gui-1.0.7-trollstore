import Foundation

/// 逐帖抓详情的全局排速器。
///
/// 站点实测规则是"每 2 秒一次"，429 正文为
/// `{"success":false,"message":"每过2秒才能试一次"}`。通知正文补全、收藏与
/// 历史页的元数据补全都要逐帖打详情，此前各自为政：进一次收藏页在 4 秒内
/// 打出 70 个请求、33 个 429，而失败的详情又会回头挤隐藏 WebView 全局锁。
/// 所有逐帖抓详情的路径共用这一个实例，才谈得上"全局"串行。
actor NodeSeekDetailRequestPacer {
    static let shared = NodeSeekDetailRequestPacer()

    enum Limit {
        static let minimumRequestInterval: TimeInterval = 2.1
        /// 并发 2 对"2 秒一次"的接口没有任何收益，只会把突发翻倍。
        static let maximumConcurrentRequests = 1
        /// 命中 429 后的全局熔断冷却。限流窗口内继续试只会把窗口拖得更长。
        static let rateLimitedCooldown: TimeInterval = 45
    }

    private var activeRequestCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastRequestStartDate: Date?
    private var rateLimitedUntil: Date?

    /// 是否正处于 429 熔断窗口内。调用方应当跳过补全，而不是排队等下去。
    func isCoolingDown() -> Bool {
        guard let rateLimitedUntil else { return false }
        return rateLimitedUntil > Date()
    }

    func noteRateLimited() {
        let now = Date()
        guard (rateLimitedUntil ?? now) <= now else { return }
        rateLimitedUntil = now.addingTimeInterval(Limit.rateLimitedCooldown)
        AppLogMetrics.shared.record(.rateLimited)
        AppLog.warning(
            .service,
            "详情排速进入熔断冷却 \(Int(Limit.rateLimitedCooldown)) 秒，期间跳过所有非必需补全"
        )
    }

    /// 取得一个抓取槽位：先串行化，再保证两次请求之间至少间隔 `minimumRequestInterval`。
    func acquire() async {
        let startedWaiting = Date()
        var queuedAhead = 0
        if activeRequestCount < Limit.maximumConcurrentRequests {
            activeRequestCount += 1
        } else {
            queuedAhead = waiters.count + 1
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        if let lastRequestStartDate {
            let delay = Limit.minimumRequestInterval - Date().timeIntervalSince(lastRequestStartDate)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        lastRequestStartDate = Date()

        if queuedAhead > 0 {
            AppLog.debug(
                .service,
                "详情排速槽位排队结束: 队列深度=\(queuedAhead), 等待=\(AppLog.elapsedMilliseconds(since: startedWaiting))ms"
            )
        }
    }

    func release() {
        if waiters.isEmpty {
            activeRequestCount = max(activeRequestCount - 1, 0)
        } else {
            waiters.removeFirst().resume()
        }
    }

    func noteCooldownSkip() {
        AppLogMetrics.shared.record(.cooldownSkips)
    }
}
