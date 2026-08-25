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
    }
}