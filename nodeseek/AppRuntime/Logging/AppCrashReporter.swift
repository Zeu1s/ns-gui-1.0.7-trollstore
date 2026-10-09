//
//  AppCrashReporter.swift
//  nodeseek
//

import CrashReporter
import Foundation

enum AppCrashReporter {
    /// 看门狗报卡死时要用同一个 reporter 现场生成调用栈，所以留一份常驻实例。
    nonisolated(unsafe) private static var liveReporter: PLCrashReporter?

    static func install() {
        let config = PLCrashReporterConfig(
            signalHandlerType: .BSD,
            symbolicationStrategy: .all,
            shouldRegisterUncaughtExceptionHandler: true
        )
        guard let reporter = PLCrashReporter(configuration: config) else { return }
        liveReporter = reporter

        if reporter.hasPendingCrashReport() {
            do {
                let data = try reporter.loadPendingCrashReportDataAndReturnError()
                let report = try PLCrashReport(data: data)
                if let text = PLCrashReportTextFormatter.stringValue(for: report, with: PLCrashReportTextFormatiOS) {
                    writeCrashReport(text)
                }
            } catch {
                AppLog.warning(.runtime, "读取崩溃报告失败: \(error.localizedDescription)")
            }
            reporter.purgePendingCrashReport()
        }

        do {
            try reporter.enableAndReturnError()
        } catch {
            AppLog.warning(.runtime, "启动崩溃监控失败: \(error.localizedDescription)")
        }
    }

    /// 卡死当场取主线程调用栈。
    ///
    /// 前两次卡死都是"渲染完成后主线程再也不吭声"，靠手工面包屑永远猜不到真凶所在，
    /// 所以改成在报卡死的那一刻现场生成一份报告，只把 Thread 0（主线程）那一段挑出来。
    /// 由看门狗所在的队列调用，不能在主线程上跑 —— 主线程本来就卡着。
    static func liveMainThreadStack() -> String? {
        guard let reporter = liveReporter,
              let data = try? reporter.generateLiveReportAndReturnError(),
              let report = try? PLCrashReport(data: data),
              let text = PLCrashReportTextFormatter.stringValue(
                  for: report,
                  with: PLCrashReportTextFormatiOS
              ) else {
            return nil
        }
        return mainThreadSection(of: text)
    }

    /// 报告里主线程那一段形如 `Thread 0 name:  ...` / `Thread 0:` 后跟若干帧，
    /// 到下一个空行为止。只保留前 24 帧，够定位又不会撑爆一行日志。
    private static func mainThreadSection(of text: String) -> String? {
        var lines: [String] = []
        var inside = false
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if inside {
                if line.isEmpty { break }
                lines.append(line)
                if lines.count >= 24 { break }
                continue
            }
            if line.hasPrefix("Thread 0") { inside = true }
        }
        guard lines.isEmpty == false else { return nil }
        return lines.joined(separator: " | ")
    }

    private static func writeCrashReport(_ text: String) {
        let directory = AppLog.fileLogURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("nodeseek-crash-\(formatter.string(from: Date())).log")
        let header = "崩溃时间: \(Date())\n"
        try? (header + text).write(to: url, atomically: true, encoding: .utf8)
        AppLog.important(.error, .runtime, "已保存崩溃报告: \(url.lastPathComponent)")
        // 崩溃堆栈全文同步写入监控日志：导出监控日志即可获得完整崩溃数据，
        // 不依赖单独的 crash 文件。
        AppLog.important(.error, .runtime, "===== 崩溃报告开始 =====")
        for chunk in Self.chunked(text, size: 3_800) {
            AppLog.important(.error, .runtime, chunk)
        }
        AppLog.important(.error, .runtime, "===== 崩溃报告结束 =====")
    }

    private static func chunked(_ text: String, size: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in text.components(separatedBy: "\n") {
            if current.count + line.count + 1 > size, current.isEmpty == false {
                chunks.append(current)
                current = ""
            }
            current += line + "\n"
        }
        if current.isEmpty == false {
            chunks.append(current)
        }
        return chunks
    }
}