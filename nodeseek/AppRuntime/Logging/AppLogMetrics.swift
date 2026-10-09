import Foundation

/// 可聚合计数项。名字直接进日志，所以用中文，省得再看表。
nonisolated enum AppLogMetric: String, CaseIterable {
    case detailRequests = "详情请求"
    case rateLimited = "命中429"
    case serverError = "服务端5xx"
    case webViewPageLoads = "WebView整页"
    case getInfo = "getInfo"
    case cooldownSkips = "熔断跳过"
}

/// 一个启动周期内的聚合计数 + 每 60 秒一行心跳。
///
/// 加这个是因为之前只能逐行数：要判断"锁是不是被占死了"，得把几十行
/// `totalMs=` 拉出来自己算中位数和最大值，一份日志看十分钟还看不准。
/// 心跳把这些压成一行，扫一眼就能定性；也顺带证明这段时间进程是活的
/// —— 否则"没发生什么"和"没在记录"在日志里长得一模一样。
nonisolated final class AppLogMetrics: @unchecked Sendable {
    static let shared = AppLogMetrics()

    private static let windowSeconds: TimeInterval = 60

    private let lock = NSLock()
    private var counters: [AppLogMetric: Int] = [:]
    private var maxima: [String: Int] = [:]
    private var totals: [String: Int] = [:]
    private var samples: [String: Int] = [:]
    private var windowStart = Date()
    private var heartbeatTask: Task<Void, Never>?

    private init() {}

    func record(_ metric: AppLogMetric, by amount: Int = 1) {
        lock.lock()
        counters[metric, default: 0] += amount
        lock.unlock()
    }

    /// 记录一次耗时，累计进"最长 / 平均 / 次数"。
    func recordDuration(_ name: String, milliseconds: Int) {
        lock.lock()
        maxima[name, default: 0] = max(maxima[name] ?? 0, milliseconds)
        totals[name, default: 0] += milliseconds
        samples[name, default: 0] += 1
        lock.unlock()
    }

    /// 重复调用只会起一个心跳。
    func startHeartbeat() {
        lock.lock()
        if heartbeatTask == nil {
            windowStart = Date()
            heartbeatTask = Task { [weak self] in
                while true {
                    try? await Task.sleep(nanoseconds: UInt64(Self.windowSeconds * 1_000_000_000))
                    guard let self else { return }
                    AppLog.info(.runtime, self.consumeWindowSummary())
                }
            }
        }
        lock.unlock()
    }

    /// 取出并清零当前窗口。窗口内什么都没发生时输出"空闲"，
    /// 这样"这段时间确实没请求"和"心跳没跑"能区分开。
    func consumeWindowSummary() -> String {
        lock.lock()
        let elapsed = max(1, Int(Date().timeIntervalSince(windowStart)))
        let capturedCounters = counters
        let capturedMaxima = maxima
        let capturedTotals = totals
        let capturedSamples = samples
        counters = [:]
        maxima = [:]
        totals = [:]
        samples = [:]
        windowStart = Date()
        lock.unlock()

        var parts: [String] = []
        for metric in AppLogMetric.allCases {
            if let value = capturedCounters[metric], value > 0 {
                parts.append("\(metric.rawValue)=\(value)")
            }
        }
        for name in capturedMaxima.keys.sorted() {
            let peak = capturedMaxima[name] ?? 0
            let count = capturedSamples[name] ?? 0
            let average = count > 0 ? (capturedTotals[name] ?? 0) / count : 0
            parts.append("\(name) 最长=\(peak)ms 平均=\(average)ms 次数=\(count)")
        }
        return "周期汇总(\(elapsed)s): \(parts.isEmpty ? "空闲" : parts.joined(separator: ", "))"
    }
}
