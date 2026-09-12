//
//  AppCrashReporter.swift
//  nodeseek
//

import CrashReporter
import Foundation

enum AppCrashReporter {
    static func install() {
        let config = PLCrashReporterConfig(
            signalHandlerType: .BSD,
            symbolicationStrategy: .all,
            shouldRegisterUncaughtExceptionHandler: true
        )
        guard let reporter = PLCrashReporter(configuration: config) else { return }

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