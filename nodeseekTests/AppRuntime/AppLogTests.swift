//
//  AppLogTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/2.
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct AppLogTests {
    @Test func fileLoggingDefaultsToDisabled() async throws {
        await FileLoggingTestGate.shared.withExclusiveAccess {
            let previousFileLoggingEnabled = NodeSeekDebugConfig.enableFileLogging
            let previousAvatarLoggingEnabled = NodeSeekDebugConfig.enableAvatarImageLogs
            defer {
                NodeSeekDebugConfig.enableFileLogging = previousFileLoggingEnabled
                NodeSeekDebugConfig.enableAvatarImageLogs = previousAvatarLoggingEnabled
            }

            NodeSeekDebugConfig.resetRuntimeLoggingForTesting()

            #expect(NodeSeekDebugConfig.enableFileLogging == false)
        }
    }

    @Test func fileLoggingWritesOnlyWhenDebugSwitchIsEnabled() async throws {
        try await withTemporaryFileLogging { directory in
            NodeSeekDebugConfig.enableFileLogging = false
            AppLog.info(.service, "disabled message")
            AppLog.flushFileLogsForTesting()
            #expect(FileManager.default.fileExists(atPath: logURL(in: directory).path) == false)

            NodeSeekDebugConfig.enableFileLogging = true
            AppLog.warning(.webView, "enabled message")
            AppLog.flushFileLogsForTesting()

            let content = try String(contentsOf: logURL(in: directory), encoding: .utf8)
            #expect(content.contains("[warning] [WebView] ["))
            #expect(content.contains("enabled message"))
            #expect(content.contains("disabled message") == false)
        }
    }

    @Test func fileLoggingSwitchPersistsPreferenceToUserDefaults() async throws {
        await FileLoggingTestGate.shared.withExclusiveAccess {
            let defaults = UserDefaults.standard
            let storageKey = NodeSeekDebugConfig.fileLoggingStorageKeyForTesting
            let previousValue = defaults.object(forKey: storageKey)
            let previousFileLoggingEnabled = NodeSeekDebugConfig.enableFileLogging
            defer {
                if let previousValue {
                    defaults.set(previousValue, forKey: storageKey)
                } else {
                    defaults.removeObject(forKey: storageKey)
                }
                NodeSeekDebugConfig.enableFileLogging = previousFileLoggingEnabled
            }

            defaults.removeObject(forKey: storageKey)
            NodeSeekDebugConfig.resetRuntimeLoggingForTesting()
            NodeSeekDebugConfig.enableFileLogging = true

            #expect(defaults.bool(forKey: storageKey) == true)
        }
    }

    @Test func readsCurrentFileLogContent() async throws {
        try await withTemporaryFileLogging { _ in
            AppLog.info(.postDetail, "detail log message")
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()

            #expect(AppLog.fileLogURL.lastPathComponent == "nodeseek.log")
            #expect(content.contains("[info] [PostDetail] ["))
            #expect(content.contains("detail log message"))
        }
    }

    @Test func exportsCurrentFileLogAsShareableCopy() async throws {
        try await withTemporaryFileLogging { _ in
            AppLog.notice(.postDetail, "exported monitoring message")
            AppLog.flushFileLogsForTesting()

            let exportURL = try AppLog.exportFileLog()
            defer { try? FileManager.default.removeItem(at: exportURL) }

            #expect(exportURL.lastPathComponent.hasPrefix("nodeseek-monitor-"))
            #expect(exportURL.pathExtension == "log")
            let content = try String(contentsOf: exportURL, encoding: .utf8)
            #expect(content.contains("exported monitoring message"))
        }
    }
    @Test func listsReadsExportsAndDeletesSingleSegmentLog() async throws {
        try await withTemporaryFileLogging { directory in
            let segmentURL = directory.appendingPathComponent("nodeseek-monitor-20260824-1200.log")
            try Data("hello segment".utf8).write(to: segmentURL)

            let files = try AppLog.logFiles()
            guard let file = files.first(where: { $0.url.lastPathComponent == segmentURL.lastPathComponent }) else {
                Issue.record("Segment log file was not listed.")
                return
            }

            let content = try AppLog.fileLogContent(for: file)
            #expect(content.contains("hello segment"))

            let exportURL = try AppLog.exportFileLog(file)
            defer { try? FileManager.default.removeItem(at: exportURL) }
            #expect(FileManager.default.fileExists(atPath: exportURL.path) == true)

            try AppLog.deleteFileLog(file)
            let remaining = try AppLog.logFiles()
            #expect(remaining.contains { $0.url == file.url } == false)
        }
    }

    @Test func listsReadsExportsAndDeletesCrashReportFile() async throws {
        try await withTemporaryFileLogging { directory in
            let crashURL = directory.appendingPathComponent("nodeseek-crash-20260824-153045.log")
            try Data("crash report body".utf8).write(to: crashURL)

            let files = try AppLog.logFiles()
            guard let file = files.first(where: { $0.url.lastPathComponent == crashURL.lastPathComponent }) else {
                Issue.record("Crash report file was not listed.")
                return
            }

            #expect(file.displayName.contains("崩溃报告"))
            let content = try AppLog.fileLogContent(for: file)
            #expect(content.contains("crash report body"))

            let exportURL = try AppLog.exportFileLog(file)
            defer { try? FileManager.default.removeItem(at: exportURL) }
            #expect(FileManager.default.fileExists(atPath: exportURL.path) == true)

            try AppLog.deleteFileLog(file)
            let remaining = try AppLog.logFiles()
            #expect(remaining.contains { $0.url == file.url } == false)
        }
    }

    @Test func logFilesReadsSegmentWithInvalidUTF8WithoutFailing() async throws {
        try await withTemporaryFileLogging { directory in
            let segmentURL = directory.appendingPathComponent("nodeseek-monitor-20260824-1200.log")
            let invalidData = Data([0x41, 0xFF, 0x42])
            try invalidData.write(to: segmentURL)

            let files = try AppLog.logFiles()
            guard let file = files.first(where: { $0.url.lastPathComponent == segmentURL.lastPathComponent }) else {
                Issue.record("Segment log file was not listed.")
                return
            }
            let content = try AppLog.fileLogContent(for: file)

            #expect(content.contains("A") == true)
            #expect(content.contains("B") == true)
            #expect(content.contains("\u{FFFD}") == true)
        }
    }

    @Test func deleteFileLogRemovesCurrentLogFile() async throws {
        try await withTemporaryFileLogging { _ in
            AppLog.info(.service, "log before delete")
            AppLog.flushFileLogsForTesting()

            try AppLog.deleteFileLog()

            #expect(FileManager.default.fileExists(atPath: AppLog.fileLogURL.path) == false)
            #expect(try AppLog.fileLogContent() == "")
        }
    }

    @Test func avatarImageLogsAreSkippedWhenDebugSwitchIsDisabled() async throws {
        try await withTemporaryFileLogging(avatarImageLogs: false) { _ in
            AvatarImageLoader(cookieBridge: CookieBridge()).loadAvatar(
                into: UIImageView(),
                postID: "avatar-log-test",
                avatarURL: nil
            )
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()
            #expect(content.contains("头像URL缺失或非法") == false)
        }
    }

    private func withTemporaryFileLogging(
        avatarImageLogs: Bool? = nil,
        _ body: (URL) throws -> Void
    ) async throws {
        try await FileLoggingTestGate.shared.withExclusiveAccess {
            let previousFileLoggingEnabled = NodeSeekDebugConfig.enableFileLogging
            let previousAvatarLoggingEnabled = NodeSeekDebugConfig.enableAvatarImageLogs
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: directory)
                NodeSeekDebugConfig.enableFileLogging = previousFileLoggingEnabled
                NodeSeekDebugConfig.enableAvatarImageLogs = previousAvatarLoggingEnabled
                AppLog.setFileLogDirectoryForTesting(nil)
            }

            AppLog.setFileLogDirectoryForTesting(directory)
            NodeSeekDebugConfig.enableFileLogging = true
            if let avatarImageLogs {
                NodeSeekDebugConfig.enableAvatarImageLogs = avatarImageLogs
            }

            try body(directory)
        }
    }

    private func logURL(in directory: URL) -> URL {
        directory.appendingPathComponent("nodeseek.log")
    }
}
