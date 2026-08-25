//
//  NotificationViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/6/8.
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct NotificationViewControllerTests {
    @Test func failedSingleMarkReadRestoresUnreadCountAndRowState() async throws {
        let client = StubNotificationViewClient(
            unreadCount: NodeSeekNotificationUnreadCount(message: 0, atMe: 1, reply: 0, all: 1),
            atMeRecords: [makeNotificationRecord(id: 3056861, viewed: 0)],
            markViewedError: URLError(.badServerResponse)
        )
        let viewController = NotificationViewController(client: client, currentAccountStore: makeCurrentAccountStore())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        let tableView = try #require(viewController.view.firstSubview(of: UITableView.self))
        let segmentedControl = try #require(viewController.view.firstSubview(of: UISegmentedControl.self))
        try await waitUntil {
            tableView.numberOfRows(inSection: 0) == 1
                && segmentedControl.titleForSegment(at: NodeSeekNotificationTab.atMe.rawValue) == "@我 1"
        }

        let cell = viewController.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        let unreadIndicator = try #require(cell.firstView(accessibilityIdentifier: "notification-sender-unread-indicator"))
        #expect(unreadIndicator.isHidden == false)
        let markReadButton = try #require(cell.firstButton(accessibilityIdentifier: "notification-mark-read-button"))
        #expect(markReadButton.isHidden == false)
        markReadButton.sendActions(for: .touchUpInside)

        try await waitUntilAsync {
            await client.markViewedCallCount() == 1
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(segmentedControl.titleForSegment(at: NodeSeekNotificationTab.atMe.rawValue) == "@我 1")
        let rollbackCell = viewController.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        let rollbackButton = try #require(rollbackCell.firstButton(accessibilityIdentifier: "notification-mark-read-button"))
        #expect(rollbackButton.isHidden == false)
    }

    @Test func selectingUnreadMessageConversationMarksMessageViewedBeforeOpeningConversation() async throws {
        let client = StubNotificationViewClient(
            unreadCount: NodeSeekNotificationUnreadCount(message: 1, atMe: 0, reply: 0, all: 1),
            messageRecords: [
                NodeSeekMessageConversationRecord(
                    receiverID: 31037,
                    senderID: 14496,
                    maxID: 920,
                    content: "hello",
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    viewed: 0,
                    senderName: "kiya",
                    receiverName: "mistj"
                )
            ]
        )
        let publishedUnreadCounts = PublishedUnreadCounts()
        let observer = NotificationCenter.default.addObserver(
            forName: .nodeSeekNotificationUnreadCountDidUpdate,
            object: nil,
            queue: .main
        ) { notification in
            guard let unreadCount = NodeSeekNotificationUnreadCountEvent.unreadCount(from: notification) else { return }
            Task { @MainActor in
                publishedUnreadCounts.append(unreadCount)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        let currentAccountStore = makeCurrentAccountStore()
        await currentAccountStore.save(
            AccountResponse(
                displayName: "mistj",
                isLoggedIn: true,
                profileURL: URL(string: "https://www.nodeseek.com/space/31037")
            )
        )
        let viewController = NotificationViewController(client: client, currentAccountStore: currentAccountStore)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        let tableView = try #require(viewController.view.firstSubview(of: UITableView.self))
        let segmentedControl = try #require(viewController.view.firstSubview(of: UISegmentedControl.self))
        segmentedControl.selectedSegmentIndex = NodeSeekNotificationTab.message.rawValue
        segmentedControl.sendActions(for: .valueChanged)

        try await waitUntil {
            tableView.numberOfRows(inSection: 0) == 1
                && segmentedControl.titleForSegment(at: NodeSeekNotificationTab.message.rawValue) == "私信 1"
        }
        let messageCell = viewController.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        let unreadIndicator = try #require(messageCell.firstView(accessibilityIdentifier: "notification-sender-unread-indicator"))
        #expect(unreadIndicator.isHidden == false)

        viewController.tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 0))

        try await waitUntilAsync {
            await client.markViewedCalls() == [
                StubNotificationViewClient.MarkViewedCall(ids: [920], tab: .message)
            ]
        }
        try await waitUntil {
            segmentedControl.titleForSegment(at: NodeSeekNotificationTab.message.rawValue) == "私信"
        }
        let readMessageCell = viewController.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        let readUnreadIndicator = try #require(readMessageCell.firstView(accessibilityIdentifier: "notification-sender-unread-indicator"))
        #expect(readUnreadIndicator.isHidden == true)
        try await waitUntil {
            publishedUnreadCounts.values.last == .zero
        }
        try await waitUntil {
            navigationController.topViewController is PrivateMessageViewController
        }
        #expect(navigationController.topViewController is PrivateMessageViewController)
    }

    @Test func allReadButtonMarksEveryNotificationCategoryAsRead() async throws {
        let client = StubNotificationViewClient(
            unreadCount: NodeSeekNotificationUnreadCount(message: 1, atMe: 1, reply: 1, all: 3),
            atMeRecords: [makeNotificationRecord(id: 3056861, viewed: 0)]
        )
        let viewController = NotificationViewController(client: client, currentAccountStore: makeCurrentAccountStore())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        let tableView = try #require(viewController.view.firstSubview(of: UITableView.self))
        try await waitUntil {
            tableView.numberOfRows(inSection: 0) == 1
        }
        let markAllButton = try #require(viewController.navigationItem.rightBarButtonItems?.first(where: { $0.title == "全部已读" }))
        #expect(markAllButton.isEnabled == true)
        let target = try #require(markAllButton.target as? NSObject)
        let action = try #require(markAllButton.action)
        _ = target.perform(action)

        try await waitUntilAsync {
            await client.markAllViewedCalls() == NodeSeekNotificationTab.allCases
        }
        try await waitUntil {
            markAllButton.isEnabled == false
        }
    }

    @Test func appActivationUsesSharedPrefetchInsteadOfDuplicatingVisibleListRequest() async throws {
        let client = StubNotificationViewClient(
            unreadCount: NodeSeekNotificationUnreadCount(message: 0, atMe: 1, reply: 0, all: 1),
            atMeRecords: [makeNotificationRecord(id: 3056861, viewed: 0)]
        )
        let viewController = NotificationViewController(client: client, currentAccountStore: makeCurrentAccountStore())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        try await waitUntilAsync {
            await client.loadAtMeCallCount() == 1
        }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        try await Task.sleep(nanoseconds: 100_000_000)
        let refreshedAtMeCallCount = await client.loadAtMeCallCount()
        #expect(refreshedAtMeCallCount == 1)
    }

    @Test func appLevelPrefetchCachesReplyAndMessageAfterAtMeCompletes() async throws {
        let ownerID = Int.random(in: 100_000_000...999_999_999)
        let currentAccountStore = makeCurrentAccountStore()
        await currentAccountStore.save(
            AccountResponse(
                displayName: "mistj",
                isLoggedIn: true,
                profileURL: URL(string: "https://www.nodeseek.com/space/\(ownerID)")
            )
        )
        let client = StubNotificationViewClient(
            unreadCount: NodeSeekNotificationUnreadCount(message: 1, atMe: 1, reply: 1, all: 3),
            atMeRecords: [makeNotificationRecord(id: 301, viewed: 0)],
            replyRecords: [makeNotificationRecord(id: 302, viewed: 0)],
            messageRecords: [
                NodeSeekMessageConversationRecord(
                    receiverID: ownerID,
                    senderID: 24060,
                    maxID: 920,
                    content: "hello",
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    viewed: 0,
                    senderName: "kiya",
                    receiverName: "mistj"
                )
            ],
            atMeLoadDelayNanoseconds: 180_000_000
        )
        let prefetcher = NodeSeekNotificationPrefetcher(
            client: client,
            currentAccountStore: currentAccountStore,
            contentResolver: EmptyNotificationContentResolver()
        )
        defer { prefetcher.stop() }

        prefetcher.refreshNow()
        try await waitUntilAsync {
            await client.loadAtMeCallCount() == 1
        }
        let replyLoadCountBeforeAtMeCompletion = await client.loadReplyCallCount()
        let messageLoadCountBeforeAtMeCompletion = await client.loadMessageCallCount()
        #expect(replyLoadCountBeforeAtMeCompletion == 0)
        #expect(messageLoadCountBeforeAtMeCompletion == 0)

        try await waitUntil {
            guard let snapshot = NodeSeekNotificationMemoryCache.shared.snapshot(for: ownerID) else {
                return false
            }
            return snapshot.atMeRecords?.map(\.id) == [301]
                && snapshot.replyRecords?.map(\.id) == [302]
                && snapshot.messageRecords?.map(\.maxID) == [920]
                && snapshot.unreadCount == NodeSeekNotificationUnreadCount(message: 1, atMe: 1, reply: 1, all: 3)
        }
    }

    @Test func foregroundPrefetchWaitsForInitialHomePreviewRequest() async throws {
        let ownerID = Int.random(in: 100_000_000...999_999_999)
        let currentAccountStore = makeCurrentAccountStore()
        await currentAccountStore.save(
            AccountResponse(
                displayName: "mistj",
                isLoggedIn: true,
                profileURL: URL(string: "https://www.nodeseek.com/space/\(ownerID)")
            )
        )
        let client = StubNotificationViewClient(
            unreadCount: .zero,
            atMeRecords: [makeNotificationRecord(id: 303, viewed: 1)]
        )
        let prefetcher = NodeSeekNotificationPrefetcher(
            client: client,
            currentAccountStore: currentAccountStore,
            contentResolver: EmptyNotificationContentResolver()
        )
        defer { prefetcher.stop() }

        prefetcher.resumeAfterForegroundActivationIfReady()
        try await Task.sleep(nanoseconds: 50_000_000)
        let callCountBeforeHomePreview = await client.loadAtMeCallCount()
        #expect(callCountBeforeHomePreview == 0)

        prefetcher.startAfterHomePreviewRequest()
        try await waitUntilAsync {
            await client.loadAtMeCallCount() == 1
        }
    }

    @Test func appLevelPrefetchResolvesCommentContentBeforeNotificationScreenOpens() async throws {
        let ownerID = Int.random(in: 100_000_000...999_999_999)
        let currentAccountStore = makeCurrentAccountStore()
        await currentAccountStore.save(
            AccountResponse(
                displayName: "mistj",
                isLoggedIn: true,
                profileURL: URL(string: "https://www.nodeseek.com/space/\(ownerID)")
            )
        )
        let atMeRecord = makeNotificationRecord(id: 304, viewed: 0)
        let replyRecord = makeNotificationRecord(id: 305, viewed: 1)
        let resolver = StubNotificationContentResolver(
            resolvedContentByRecordID: [
                atMeRecord.id: .init(content: "@我的回帖正文", page: 4),
                replyRecord.id: .init(content: "回复主题正文", page: 5)
            ]
        )
        let prefetcher = NodeSeekNotificationPrefetcher(
            client: StubNotificationViewClient(
                unreadCount: NodeSeekNotificationUnreadCount(message: 0, atMe: 1, reply: 0, all: 1),
                atMeRecords: [atMeRecord],
                replyRecords: [replyRecord]
            ),
            currentAccountStore: currentAccountStore,
            contentResolver: resolver
        )
        defer { prefetcher.stop() }

        prefetcher.refreshNow()

        try await waitUntil {
            guard let snapshot = NodeSeekNotificationMemoryCache.shared.snapshot(for: ownerID) else {
                return false
            }
            return snapshot.atMeRecords?.first?.content == "@我的回帖正文"
                && snapshot.atMeRecords?.first?.resolvedCommentPage == 4
                && snapshot.replyRecords?.first?.content == "回复主题正文"
                && snapshot.replyRecords?.first?.resolvedCommentPage == 5
        }
    }

    @Test func notificationTabsArePrefetchedAndRefreshWhenSwitched() async throws {
        let client = StubNotificationViewClient(
            unreadCount: .zero,
            atMeRecords: [makeNotificationRecord(id: 101, viewed: 1)],
            replyRecords: [makeNotificationRecord(id: 102, viewed: 1)],
            atMeLoadDelayNanoseconds: 180_000_000
        )
        let viewController = NotificationViewController(client: client, currentAccountStore: makeCurrentAccountStore())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        try await waitUntilAsync {
            await client.loadAtMeCallCount() == 1
        }
        let replyLoadCountBeforeAtMeCompletion = await client.loadReplyCallCount()
        let messageLoadCountBeforeAtMeCompletion = await client.loadMessageCallCount()
        #expect(replyLoadCountBeforeAtMeCompletion == 0)
        #expect(messageLoadCountBeforeAtMeCompletion == 0)

        try await waitUntilAsync {
            let replyLoadCount = await client.loadReplyCallCount()
            let messageLoadCount = await client.loadMessageCallCount()
            return replyLoadCount == 1 && messageLoadCount == 1
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        let segmentedControl = try #require(viewController.view.firstSubview(of: UISegmentedControl.self))
        segmentedControl.selectedSegmentIndex = NodeSeekNotificationTab.reply.rawValue
        segmentedControl.sendActions(for: .valueChanged)

        try await waitUntilAsync {
            await client.loadReplyCallCount() == 2
        }
    }
}

@MainActor
private final class PublishedUnreadCounts {
    private(set) var values: [NodeSeekNotificationUnreadCount] = []

    func append(_ unreadCount: NodeSeekNotificationUnreadCount) {
        values.append(unreadCount)
    }
}

private func makeNotificationRecord(id: Int, viewed: Int) -> NodeSeekNotificationRecord {
    NodeSeekNotificationRecord(
        id: id,
        viewed: viewed,
        commentID: 10503771,
        floorID: 11,
        createdAt: Date(timeIntervalSince1970: 1_000),
        commenterID: 24060,
        title: "通知标题",
        postID: 763505,
        firstCommentID: 10501640,
        commenterName: "kiya"
    )
}

private func makeCurrentAccountStore() -> CurrentAccountStore {
    let suiteName = "notification-view-controller-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return CurrentAccountStore(userDefaults: defaults, storageKey: "account")
}

private actor StubNotificationViewClient: NodeSeekNotificationClientProtocol {
    struct MarkViewedCall: Equatable {
        let ids: [Int]
        let tab: NodeSeekNotificationTab
    }

    private var unreadCount: NodeSeekNotificationUnreadCount
    private var atMeRecords: [NodeSeekNotificationRecord]
    private var replyRecords: [NodeSeekNotificationRecord]
    private var messageRecords: [NodeSeekMessageConversationRecord]
    private let markViewedError: Error?
    private let atMeLoadDelayNanoseconds: UInt64
    private var markViewedCallValues: [MarkViewedCall] = []
    private var markAllViewedTabValues: [NodeSeekNotificationTab] = []
    private var atMeLoadCount = 0
    private var replyLoadCount = 0
    private var messageLoadCount = 0

    init(
        unreadCount: NodeSeekNotificationUnreadCount,
        atMeRecords: [NodeSeekNotificationRecord] = [],
        replyRecords: [NodeSeekNotificationRecord] = [],
        messageRecords: [NodeSeekMessageConversationRecord] = [],
        markViewedError: Error? = nil,
        atMeLoadDelayNanoseconds: UInt64 = 0
    ) {
        self.unreadCount = unreadCount
        self.atMeRecords = atMeRecords
        self.replyRecords = replyRecords
        self.messageRecords = messageRecords
        self.markViewedError = markViewedError
        self.atMeLoadDelayNanoseconds = atMeLoadDelayNanoseconds
    }

    func markViewedCallCount() -> Int {
        markViewedCallValues.count
    }

    func markViewedCalls() -> [MarkViewedCall] {
        markViewedCallValues
    }

    func markAllViewedCalls() -> [NodeSeekNotificationTab] {
        markAllViewedTabValues
    }

    func loadAtMeCallCount() -> Int {
        atMeLoadCount
    }

    func loadReplyCallCount() -> Int {
        replyLoadCount
    }

    func loadMessageCallCount() -> Int {
        messageLoadCount
    }

    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount {
        unreadCount
    }

    func loadAtMe() async throws -> [NodeSeekNotificationRecord] {
        atMeLoadCount += 1
        if atMeLoadDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: atMeLoadDelayNanoseconds)
        }
        atMeRecords
    }

    func loadReplies() async throws -> [NodeSeekNotificationRecord] {
        replyLoadCount += 1
        replyRecords
    }

    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord] {
        messageLoadCount += 1
        messageRecords
    }

    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws {
        markViewedCallValues.append(MarkViewedCall(ids: ids, tab: tab))
        if let markViewedError {
            throw markViewedError
        }
        unreadCount.decrement(for: tab, by: ids.count)
    }

    func markAllViewed(tab: NodeSeekNotificationTab) async throws {
        markAllViewedTabValues.append(tab)
        unreadCount.setCount(0, for: tab)
    }
}

private actor EmptyNotificationContentResolver: NodeSeekNotificationContentResolving {
    func resolveContent(
        for record: NodeSeekNotificationRecord
    ) async -> NodeSeekNotificationContentResolver.ResolvedContent? {
        nil
    }
}

private actor StubNotificationContentResolver: NodeSeekNotificationContentResolving {
    private let resolvedContentByRecordID: [Int: NodeSeekNotificationContentResolver.ResolvedContent]

    init(resolvedContentByRecordID: [Int: NodeSeekNotificationContentResolver.ResolvedContent]) {
        self.resolvedContentByRecordID = resolvedContentByRecordID
    }

    func resolveContent(
        for record: NodeSeekNotificationRecord
    ) async -> NodeSeekNotificationContentResolver.ResolvedContent? {
        resolvedContentByRecordID[record.id]
    }
}

private extension UIView {
    func firstSubview<View: UIView>(of type: View.Type) -> View? {
        if let view = self as? View {
            return view
        }
        for subview in subviews {
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }

    func firstButton(accessibilityIdentifier: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }
        for subview in subviews {
            if let match = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }
        return nil
    }

    func firstView(accessibilityIdentifier: String) -> UIView? {
        if self.accessibilityIdentifier == accessibilityIdentifier {
            return self
        }
        for subview in subviews {
            if let match = subview.firstView(accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }
        return nil
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let step: UInt64 = 25_000_000
    var waited: UInt64 = 0
    while waited < timeoutNanoseconds {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
}

private func waitUntilAsync(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping () async -> Bool
) async throws {
    let step: UInt64 = 25_000_000
    var waited: UInt64 = 0
    while waited < timeoutNanoseconds {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
}
