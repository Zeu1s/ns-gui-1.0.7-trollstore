//
//  CurrentAccountStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import Foundation

actor CurrentAccountStore {
    nonisolated struct Snapshot: Equatable, Sendable {
        let account: AccountResponse
        let updatedAt: Date
    }

    nonisolated static let shared = CurrentAccountStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private var cachedSnapshot: Snapshot?

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "com.nodeseek.current-account"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.cachedSnapshot = Self.loadSnapshot(userDefaults: userDefaults, storageKey: storageKey)
        Self.lastLoadedSnapshot = cachedSnapshot
    }

    func snapshot() -> Snapshot? {
        cachedSnapshot
    }

    /// 供 MainActor 代码同步取当前用户 ID（从启动时已加载的缓存快照读取，不进 actor 队列）。
    nonisolated func syncCachedUserID() -> Int? {
        Self.lastLoadedSnapshot?.account.nodeSeekUID
    }

    private static var lastLoadedSnapshot: Snapshot?

    func save(_ account: AccountResponse, updatedAt: Date = Date()) {
        let snapshot = Snapshot(account: account, updatedAt: updatedAt)
        cachedSnapshot = snapshot
        Self.lastLoadedSnapshot = snapshot
        persist(snapshot)
    }

    func clear() {
        cachedSnapshot = nil
        Self.lastLoadedSnapshot = nil
        userDefaults.removeObject(forKey: storageKey)
    }

    func markStale(now: Date = Date.distantPast) {
        guard let snapshot = cachedSnapshot else { return }
        let updated = Snapshot(account: snapshot.account, updatedAt: now)
        cachedSnapshot = updated
        persist(updated)
    }

    func shouldRefresh(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        guard maxAge > 0 else { return true }
        guard let snapshot = cachedSnapshot else { return true }
        return now.timeIntervalSince(snapshot.updatedAt) > maxAge
    }

    private func persist(_ snapshot: Snapshot) {
        let persisted = Persisted(snapshot: snapshot)
        do {
            let data = try JSONEncoder().encode(persisted)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            // 持久化失败不应影响正常使用；下次刷新可纠正。
        }
    }

    private static func loadSnapshot(userDefaults: UserDefaults, storageKey: String) -> Snapshot? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        do {
            let persisted = try JSONDecoder().decode(Persisted.self, from: data)
            return persisted.snapshot
        } catch {
            return nil
        }
    }
}

private nonisolated struct Persisted: Codable {
    let schemaVersion: Int
    let displayName: String
    let isLoggedIn: Bool
    let avatarURL: String?
    let profileURL: String?
    let stats: [String]
    let notificationURL: String?
    let notificationIconColorCSS: String?
    let updatedAt: TimeInterval

    init(snapshot: CurrentAccountStore.Snapshot) {
        schemaVersion = 3
        displayName = snapshot.account.displayName
        isLoggedIn = snapshot.account.isLoggedIn
        avatarURL = snapshot.account.avatarURL?.absoluteString
        profileURL = snapshot.account.profileURL?.absoluteString
        stats = snapshot.account.stats
        notificationURL = snapshot.account.notification?.url.absoluteString
        notificationIconColorCSS = snapshot.account.notification?.iconColorCSS
        updatedAt = snapshot.updatedAt.timeIntervalSince1970
    }

    var snapshot: CurrentAccountStore.Snapshot {
        let notificationURL = notificationURL.flatMap(URL.init(string:))
        return CurrentAccountStore.Snapshot(
            account: AccountResponse(
                displayName: displayName,
                isLoggedIn: isLoggedIn,
                avatarURL: avatarURL.flatMap(URL.init(string:)),
                profileURL: profileURL.flatMap(URL.init(string:)),
                stats: stats,
                notification: notificationURL.map {
                    AccountNotification(url: $0, iconColorCSS: notificationIconColorCSS)
                }
            ),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
