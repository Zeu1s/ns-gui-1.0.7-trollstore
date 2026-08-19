//
//  NodeSeekUserInfoStore.swift
//  nodeseek
//

import Foundation

final class NodeSeekUserInfoStore {
    static let shared = NodeSeekUserInfoStore()
    static let didUpdateNotification = Notification.Name("NodeSeekUserInfoStore.didUpdate")

    private let client: NodeSeekUserInfoLoading
    private var cache: [Int: NodeSeekUserInfo] = [:]
    private var inflight: [Int: Task<Void, Never>] = [:]
    private var pendingIDs: [Int] = []
    private var isProcessing = false

    init(client: NodeSeekUserInfoLoading = NodeSeekUserInfoClient()) {
        self.client = client
    }

    func badgeText(for profileURL: URL?) -> String? {
        guard let userID = Self.userID(from: profileURL) else { return nil }
        return cache[userID]?.badgeText
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
        guard isProcessing == false else { return }
        guard let userID = pendingIDs.first else { return }
        pendingIDs.removeFirst()
        isProcessing = true
        let task = Task { [weak self] in
            do {
                let info = try await self?.client.loadUserInfo(userID: userID)
                await MainActor.run {
                    guard let self, let info else { return }
                    self.cache[userID] = info
                    NotificationCenter.default.post(
                        name: Self.didUpdateNotification,
                        object: nil,
                        userInfo: ["userID": userID]
                    )
                }
            } catch {
                // 单次失败不重试，避免在弱网下打满接口。
            }
            await MainActor.run {
                guard let self else { return }
                self.inflight[userID] = nil
                self.isProcessing = false
                self.processNext()
            }
        }
        inflight[userID] = task
    }

    static func userID(from profileURL: URL?) -> Int? {
        guard let profileURL else { return nil }
        let components = profileURL.pathComponents
        for (index, component) in components.enumerated() where component == "space" || component == "user" {
            let nextIndex = index + 1
            guard nextIndex < components.count else { continue }
            if let userID = Int(components[nextIndex]) {
                return userID
            }
        }
        return nil
    }
}