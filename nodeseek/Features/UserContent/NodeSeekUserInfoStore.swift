//
//  NodeSeekUserInfoStore.swift
//  nodeseek
//

import Foundation

final class NodeSeekUserInfoStore {
    static let shared = NodeSeekUserInfoStore()
    static let didUpdateNotification = Notification.Name("NodeSeekUserInfoStore.didUpdate")

    private let client: NodeSeekUserInfoLoading
    private let defaults: UserDefaults
    private var cache: [Int: NodeSeekUserInfo] = [:]
    private var inflight: [Int: Task<Void, Never>] = [:]
    private var pendingIDs: [Int] = []
    private var activeCount = 0
    private let maxConcurrent = 6

    init(client: NodeSeekUserInfoLoading = NodeSeekUserInfoClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    func badgeText(for profileURL: URL?) -> String? {
        guard let userID = Self.userID(from: profileURL) else { return nil }
        if let info = cache[userID] {
            return info.badgeText
        }
        return defaults.string(forKey: Self.cacheKey(userID))
    }

    func requestBadge(for profileURL: URL?) {
        guard let userID = Self.userID(from: profileURL) else { return }
        guard cache[userID] == nil,
              inflight[userID] == nil,
              pendingIDs.contains(userID) == false else { return }
        pendingIDs.append(userID)
        processNext()
    }

    private func processNext() {
        while activeCount < maxConcurrent, let userID = pendingIDs.first {
            pendingIDs.removeFirst()
            activeCount += 1
            let task = Task { [weak self] in
                do {
                    if let info = try await self?.client.loadUserInfo(userID: userID) {
                        await MainActor.run {
                            guard let self else { return }
                            self.cache[userID] = info
                            self.defaults.set(info.badgeText, forKey: Self.cacheKey(userID))
                            NotificationCenter.default.post(
                                name: Self.didUpdateNotification,
                                object: nil,
                                userInfo: ["userID": userID]
                            )
                        }
                    }
                } catch {
                    // 单次失败不重试，避免在弱网下打满接口。
                }
                await MainActor.run {
                    guard let self else { return }
                    self.inflight[userID] = nil
                    self.activeCount -= 1
                    self.processNext()
                }
            }
            inflight[userID] = task
        }
    }

    private static func cacheKey(_ userID: Int) -> String {
        "nodeseek.userInfo.\(userID)"
    }

    static func userID(from profileURL: URL?) -> Int? {
        profileURL.flatMap(NodeSeekUserIDResolver.uid(from:))
    }
}
