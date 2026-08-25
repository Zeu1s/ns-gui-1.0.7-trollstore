//
//  AppLog.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import Foundation
import OSLog

enum AppLogType: String, CaseIterable {
    case service = "Service"
    case webView = "WebView"
    case postList = "PostList"
    case postDetail = "PostDetail"
    case image = "Image"
    case rendering = "Rendering"
    case account = "Account"
    case autoCheckIn = "AutoCheckIn"
    case runtime = "Runtime"
}

enum AppLogLevel: String {
    case debug
    case info
    case notice
    case warning
    case error
}

enum AppLogFileExportError: LocalizedError {
    case empty

    var errorDescription: String? {
        switch self {
        case .empty:
            return "暂无可导出的监控日志。"
        }
    }
}

struct AppLogFile: Hashable {
    let url: URL
    let displayName: String
    let byteCount: Int

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

enum AppLog {
    nonisolated private static let subsystem = "com.nodeseek.app"
    nonisolated private static let fileWriter = AppLogFileWriter()
    nonisolated private static let loggers: [AppLogType: Logger] = Dictionary(
        uniqueKeysWithValues: AppLogType.allCases.map { type in
            (type, Logger(subsystem: subsystem, category: type.rawValue))
        }
    )

    nonisolated static func debug(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.debug, type, message())
    }

    nonisolated static func info(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.info, type, message())
    }

    nonisolated static func notice(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.notice, type, message())
    }

    nonisolated static func warning(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.warning, type, message())
    }

    nonisolated static func error(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.error, type, message())
    }

    nonisolated static func log(_ level: AppLogLevel, _ type: AppLogType, _ message: @autoclosure () -> String) {
        write(level, type, message())
    }

    nonisolated static var fileLogURL: URL {
        fileWriter.logURL()
    }

    nonisolated static func fileLogContent() throws -> String {
        try fileWriter.readContent()
    }

    nonisolated static func exportFileLog() throws -> URL {
        try fileWriter.exportLogFile()
    }

    nonisolated static func deleteFileLog() throws {
        try fileWriter.deleteLogFile()
    }

    nonisolated static func logFiles() throws -> [AppLogFile] {
        try fileWriter.logFiles()
    }

    nonisolated static func fileLogContent(for file: AppLogFile) throws -> String {
        try fileWriter.readContent(for: file)
    }

    nonisolated static func deleteFileLog(_ file: AppLogFile) throws {
        try fileWriter.deleteLogFile(file)
    }

    nonisolated static func deleteAllFileLogs() throws {
        try fileWriter.deleteAllLogFiles()
    }

    nonisolated static func exportFileLog(_ file: AppLogFile) throws -> URL {
        try fileWriter.exportLogFile(file)
    }

    nonisolated static func exportAllFileLogs() throws -> [URL] {
        try fileWriter.exportAllLogFiles()
    }

    nonisolated static func flushFileLogs() {
        fileWriter.flush()
    }

    nonisolated static func elapsedMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }

    #if DEBUG
    nonisolated static func setFileLogDirectoryForTesting(_ directory: URL?) {
        fileWriter.setDirectoryOverride(directory)
    }

    nonisolated static func flushFileLogsForTesting() {
        fileWriter.flush()
    }
    #endif

    nonisolated static func important(_ level: AppLogLevel, _ type: AppLogType, _ message: @autoclosure () -> String) {
        let stampedMessage = "\(messageTimestamp()) \(message())"
        let logger = loggers[type] ?? Logger(subsystem: subsystem, category: type.rawValue)
        switch level {
        case .debug:
            logger.debug("\(stampedMessage, privacy: .public)")
        case .info:
            logger.info("\(stampedMessage, privacy: .public)")
        case .notice:
            logger.notice("\(stampedMessage, privacy: .public)")
        case .warning:
            logger.warning("\(stampedMessage, privacy: .public)")
        case .error:
            logger.error("\(stampedMessage, privacy: .public)")
        }
        fileWriter.writeImmediately(level: level, type: type, message: stampedMessage)
    }

    nonisolated private static func write(_ level: AppLogLevel, _ type: AppLogType, _ message: String) {
        let stampedMessage = "\(messageTimestamp()) \(message)"
        let logger = loggers[type] ?? Logger(subsystem: subsystem, category: type.rawValue)
        switch level {
        case .debug:
            logger.debug("\(stampedMessage, privacy: .public)")
        case .info:
            logger.info("\(stampedMessage, privacy: .public)")
        case .notice:
            logger.notice("\(stampedMessage, privacy: .public)")
        case .warning:
            logger.warning("\(stampedMessage, privacy: .public)")
        case .error:
            logger.error("\(stampedMessage, privacy: .public)")
        }
        fileWriter.write(level: level, type: type, message: stampedMessage)
    }

    nonisolated static func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler(nodeSeekUncaughtExceptionHandler)
    }

    nonisolated private static func messageTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        return "[\(formatter.string(from: Date()))]"
    }
}

private let nodeSeekUncaughtExceptionHandler: @convention(c) (NSException) -> Void = { exception in
    let stack = exception.callStackSymbols.prefix(12).joined(separator: " | ")
    AppLog.important(.error, .runtime, "未捕获异常: name=\(exception.name.rawValue), reason=\(exception.reason ?? "无"), stack=\(stack)")
}

private final class AppLogFileWriter: @unchecked Sendable {
    private static let legacyFileName = "nodeseek.log"
    private static let segmentPrefix = "nodeseek-monitor-"
    private static let crashPrefix = "nodeseek-crash-"
    private static let segmentSuffix = ".log"

    private let queue = DispatchQueue(label: "com.nodeseek.app.log.file")
    nonisolated(unsafe) private var directoryOverride: URL?

    nonisolated func write(level: AppLogLevel, type: AppLogType, message: String) {
        guard NodeSeekDebugConfig.enableFileLogging else { return }
        queue.async {
            self.append(level: level, type: type, message: message)
        }
    }

    nonisolated func writeImmediately(level: AppLogLevel, type: AppLogType, message: String) {
        guard NodeSeekDebugConfig.enableFileLogging else { return }
        queue.sync {
            self.append(level: level, type: type, message: message)
        }
    }

    nonisolated func logURL() -> URL {
        queue.sync {
            Self.logURL(in: directoryOverride ?? Self.defaultDirectory(), date: Date())
        }
    }

    nonisolated func readContent() throws -> String {
        try queue.sync {
            let files = try self.files(in: self.directoryOverride ?? Self.defaultDirectory())
            return try files.reversed().map { try String(contentsOf: $0.url, encoding: .utf8) }.joined(separator: "\n")
        }
    }

    nonisolated func deleteLogFile() throws {
        try deleteAllLogFiles()
    }

    nonisolated func exportLogFile() throws -> URL {
        try queue.sync {
            let files = try self.files(in: self.directoryOverride ?? Self.defaultDirectory())
            guard files.isEmpty == false else { throw AppLogFileExportError.empty }
            let content = try files.reversed().reduce(into: Data()) { partialResult, file in
                partialResult.append(try Data(contentsOf: file.url))
            }
            guard content.isEmpty == false else { throw AppLogFileExportError.empty }
            let timestamp = Int(Date().timeIntervalSince1970)
            let exportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("nodeseek-monitor-\(timestamp).log")
            try content.write(to: exportURL, options: .atomic)
            return exportURL
        }
    }

    nonisolated func logFiles() throws -> [AppLogFile] {
        try queue.sync {
            try self.files(in: self.directoryOverride ?? Self.defaultDirectory())
        }
    }

    nonisolated func readContent(for file: AppLogFile) throws -> String {
        try queue.sync {
            let directory = self.directoryOverride ?? Self.defaultDirectory()
            guard self.isManaged(file.url, in: directory) else {
                throw CocoaError(.fileNoSuchFile)
            }
            guard FileManager.default.fileExists(atPath: file.url.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try Data(contentsOf: file.url, options: [.mappedIfSafe])
            return String(decoding: data, as: UTF8.self)
        }
    }

    nonisolated func deleteLogFile(_ file: AppLogFile) throws {
        try queue.sync {
            let directory = self.directoryOverride ?? Self.defaultDirectory()
            guard self.isManaged(file.url, in: directory) else { return }
            try FileManager.default.removeItem(at: file.url)
        }
    }

    nonisolated func deleteAllLogFiles() throws {
        try queue.sync {
            try self.deleteAllLogFiles(in: self.directoryOverride ?? Self.defaultDirectory())
        }
    }

    nonisolated func exportLogFile(_ file: AppLogFile) throws -> URL {
        try queue.sync {
            let directory = self.directoryOverride ?? Self.defaultDirectory()
            guard self.isManaged(file.url, in: directory) else {
                throw AppLogFileExportError.empty
            }
            return try self.copyForExport(file.url)
        }
    }

    nonisolated func exportAllLogFiles() throws -> [URL] {
        try queue.sync {
            let files = try self.files(in: self.directoryOverride ?? Self.defaultDirectory())
            guard files.isEmpty == false else { throw AppLogFileExportError.empty }
            return try files.map { try self.copyForExport($0.url) }
        }
    }

    #if DEBUG
    nonisolated func setDirectoryOverride(_ directory: URL?) {
        queue.sync {
            directoryOverride = directory
        }
    }
    #endif

    nonisolated func flush() {
        queue.sync {}
    }

    private func append(level: AppLogLevel, type: AppLogType, message: String) {
        let directory = directoryOverride ?? Self.defaultDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let line = "\(Self.timestamp()) [\(level.rawValue)] [\(type.rawValue)] \(message)\n"
            let logURL = Self.logURL(in: directory, date: Date())
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            Logger(subsystem: "com.nodeseek.app", category: "Logging")
                .error("文件日志写入失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func files(in directory: URL) throws -> [AppLogFile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            guard Self.isLogFileName(url.lastPathComponent) else { return nil }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return AppLogFile(
                    url: url,
                    displayName: Self.displayName(for: url.lastPathComponent, fallbackDate: values.contentModificationDate),
                    byteCount: values.fileSize ?? 0
                )
            } catch {
                Logger(subsystem: "com.nodeseek.app", category: "Logging")
                    .warning("读取日志文件属性失败，跳过该文件: \(url.lastPathComponent, privacy: .public)")
                return nil
            }
        }.sorted { lhs, rhs in
            lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }
    }

    private func deleteAllLogFiles(in directory: URL) throws {
        for file in try files(in: directory) {
            guard FileManager.default.fileExists(atPath: file.url.path) else { continue }
            try FileManager.default.removeItem(at: file.url)
        }
    }

    private func isManaged(_ url: URL, in directory: URL) -> Bool {
        let managedURL = url.standardizedFileURL
        let managedDirectory = directory.standardizedFileURL
        return managedURL.deletingLastPathComponent() == managedDirectory
            && Self.isLogFileName(managedURL.lastPathComponent)
    }

    private func copyForExport(_ sourceURL: URL) throws -> URL {
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nodeseek-\(sourceURL.lastPathComponent)")
        try? FileManager.default.removeItem(at: exportURL)
        try FileManager.default.copyItem(at: sourceURL, to: exportURL)
        return exportURL
    }

    nonisolated private static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
    }

    nonisolated private static func logURL(in directory: URL, date: Date) -> URL {
        directory.appendingPathComponent("\(segmentPrefix)\(segmentDateString(for: date))\(segmentSuffix)")
    }

    private static func isLogFileName(_ fileName: String) -> Bool {
        fileName == legacyFileName
            || (fileName.hasPrefix(segmentPrefix) && fileName.hasSuffix(segmentSuffix))
            || (fileName.hasPrefix(crashPrefix) && fileName.hasSuffix(segmentSuffix))
    }

    private static func segmentDateString(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = (components.minute ?? 0) / 10 * 10
        let normalized = calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: components.hour,
            minute: minute
        )) ?? date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: normalized)
    }

    private static func displayName(for fileName: String, fallbackDate: Date?) -> String {
        guard fileName != legacyFileName else { return "历史累计日志" }
        if fileName.hasPrefix(crashPrefix) {
            let rawValue = fileName
                .replacingOccurrences(of: crashPrefix, with: "")
                .replacingOccurrences(of: segmentSuffix, with: "")
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = .current
            parser.dateFormat = "yyyyMMdd-HHmmss"
            if let date = parser.date(from: rawValue) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.timeZone = .current
                formatter.dateFormat = "MM月dd日 HH:mm:ss"
                return "崩溃报告 \(formatter.string(from: date))"
            }
            return "崩溃报告"
        }
        let rawValue = fileName
            .replacingOccurrences(of: segmentPrefix, with: "")
            .replacingOccurrences(of: segmentSuffix, with: "")
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyyMMdd-HHmm"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM月dd日 HH:mm"
        if let date = parser.date(from: rawValue) {
            return "\(formatter.string(from: date)) - \(formatter.string(from: date.addingTimeInterval(600)))"
        }
        if let fallbackDate {
            return formatter.string(from: fallbackDate)
        }
        return fileName
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

final class AppRuntimeMonitor {
    static let shared = AppRuntimeMonitor()

    private enum StorageKey {
        static let sessionOpen = "nodeSeekMonitor.sessionOpen"
        static let sceneState = "nodeSeekMonitor.sceneState"
        static let lastHeartbeat = "nodeSeekMonitor.lastHeartbeat"
    }

    private let defaults = UserDefaults.standard
    private let stateQueue = DispatchQueue(label: "com.nodeseek.app.runtime-monitor")
    private var watchdogTimer: DispatchSourceTimer?
    private var isSceneActive = false
    private var lastMainThreadHeartbeat = Date()
    private var didReportCurrentStall = false

    private init() {}

    func applicationDidLaunch() {
        guard NodeSeekDebugConfig.enableFileLogging else { return }
        let wasForeground = defaults.bool(forKey: StorageKey.sessionOpen)
            && defaults.string(forKey: StorageKey.sceneState) == "active"
        if wasForeground {
            let timestamp = defaults.object(forKey: StorageKey.lastHeartbeat) as? Date
            AppLog.important(.error, .runtime, "检测到上一次前台会话异常结束，最后心跳=\(timestamp?.description ?? "未知")")
        }
        defaults.set(true, forKey: StorageKey.sessionOpen)
        defaults.set("launching", forKey: StorageKey.sceneState)
        defaults.set(Date(), forKey: StorageKey.lastHeartbeat)
        AppLog.important(.notice, .runtime, "监控会话启动")
    }

    func monitoringSettingDidChange(isEnabled: Bool) {
        if isEnabled {
            applicationDidLaunch()
            sceneDidBecomeActive()
        } else {
            markSessionClosed(reason: "用户关闭监控")
        }
    }

    func sceneDidBecomeActive() {
        guard NodeSeekDebugConfig.enableFileLogging else { return }
        stateQueue.async {
            self.isSceneActive = true
            self.lastMainThreadHeartbeat = Date()
            self.didReportCurrentStall = false
        }
        defaults.set(true, forKey: StorageKey.sessionOpen)
        defaults.set("active", forKey: StorageKey.sceneState)
        defaults.set(Date(), forKey: StorageKey.lastHeartbeat)
        AppLog.important(.notice, .runtime, "场景进入活跃状态")
        startWatchdogIfNeeded()
    }

    func sceneWillResignActive() {
        updateSceneState("inactive", message: "场景即将失去活跃状态")
    }

    func sceneDidEnterBackground() {
        updateSceneState("background", message: "场景进入后台")
    }

    func sceneDidDisconnect() {
        updateSceneState("disconnected", message: "场景断开")
    }

    func applicationWillTerminate() {
        markSessionClosed(reason: "应用正常终止")
    }

    private func updateSceneState(_ state: String, message: String) {
        guard NodeSeekDebugConfig.enableFileLogging else { return }
        stateQueue.async { self.isSceneActive = false }
        defaults.set(state, forKey: StorageKey.sceneState)
        defaults.set(Date(), forKey: StorageKey.lastHeartbeat)
        AppLog.important(.notice, .runtime, message)
    }

    private func markSessionClosed(reason: String) {
        stateQueue.async { self.isSceneActive = false }
        defaults.set(false, forKey: StorageKey.sessionOpen)
        defaults.set("closed", forKey: StorageKey.sceneState)
        AppLog.important(.notice, .runtime, reason)
        AppLog.flushFileLogs()
    }

    private func startWatchdogIfNeeded() {
        stateQueue.async {
            guard self.watchdogTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.stateQueue)
            timer.schedule(deadline: .now() + 3, repeating: 3)
            timer.setEventHandler { [weak self] in
                self?.scheduleMainThreadHeartbeat()
            }
            self.watchdogTimer = timer
            timer.resume()
        }
    }

    private func scheduleMainThreadHeartbeat() {
        let scheduledAt = Date()
        DispatchQueue.main.async { [weak self] in
            self?.acceptMainThreadHeartbeat(at: scheduledAt)
        }
        stateQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.reportStallIfNeeded(scheduledAt: scheduledAt)
        }
    }

    private func acceptMainThreadHeartbeat(at date: Date) {
        stateQueue.async {
            self.lastMainThreadHeartbeat = date
            self.didReportCurrentStall = false
        }
        defaults.set(date, forKey: StorageKey.lastHeartbeat)
    }

    private func reportStallIfNeeded(scheduledAt: Date) {
        guard isSceneActive,
              lastMainThreadHeartbeat < scheduledAt,
              didReportCurrentStall == false else {
            return
        }
        didReportCurrentStall = true
        AppLog.important(.error, .runtime, "主线程超过 5 秒未响应，可能发生卡死")
    }
}