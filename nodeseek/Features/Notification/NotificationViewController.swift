//
//  NotificationViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import SafariServices
import UIKit

@MainActor
final class NotificationViewController: UIViewController {
    private enum DisplayMode {
        case content
        case loading
        case error
    }

    private enum NotificationTabPayload {
        case notifications([NodeSeekNotificationRecord])
        case messages([NodeSeekMessageConversationRecord])
    }

    private let client: NodeSeekNotificationClientProtocol
    private let currentAccountStore: CurrentAccountStore
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let segmentedControl = NotificationTabSegmentedControl()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "notification-error-view")
    private let loadingView = NotificationLoadingView()
    private let emptyLabel = UILabel()
    private var browserButton: UIBarButtonItem?
    private var markAllButton: UIBarButtonItem?

    private var selectedTab: NodeSeekNotificationTab = .atMe
    private var displayMode: DisplayMode = .content
    private var atMeRecords: [NodeSeekNotificationRecord] = []
    private var replyRecords: [NodeSeekNotificationRecord] = []
    private var messageRecords: [NodeSeekMessageConversationRecord] = []
    private var loadedTabs: Set<NodeSeekNotificationTab> = []
    private var unreadCount: NodeSeekNotificationUnreadCount = .zero
    private var currentUserID: Int?
    private var tabLoadTokens: [NodeSeekNotificationTab: Int] = [:]
    private var loadingTabs: Set<NodeSeekNotificationTab> = []
    private var pendingRefreshTabs: Set<NodeSeekNotificationTab> = []
    private var refreshFeedbackTab: NodeSeekNotificationTab?
    private var hasAppeared = false
    private var tabContentOffsets: [NodeSeekNotificationTab: CGPoint] = [:]
    private var commentContentEnrichmentTasks: [NodeSeekNotificationTab: Task<Void, Never>] = [:]
    private var commentContentEnrichmentTokens: [NodeSeekNotificationTab: Int] = [:]
    private var pendingStreamRecordIDs: [NodeSeekNotificationTab: Set<Int>] = [:]
    private var hasCompletedInitialAtMeLoad = false
    private weak var tabSwipePanGesture: UIPanGestureRecognizer?
    private var suppressRowSelectionUntil = Date.distantPast

    private static let maxConcurrentCommentContentLoads = 2
    private static let maximumCommentContentEnrichmentRecords = 12
    private static let maximumStreamedNewRowCount = 12

    init(
        client: NodeSeekNotificationClientProtocol? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
        self.client = client ?? NodeSeekNotificationClient()
        self.currentAccountStore = currentAccountStore
        super.init(nibName: nil, bundle: nil)
        title = "通知"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userInfoDidUpdate(_:)),
            name: NodeSeekUserInfoStore.didUpdateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notificationCacheDidUpdate(_:)),
            name: .nodeSeekNotificationCacheDidUpdate,
            object: nil
        )
        loadInitialNotificationData()
    }

    deinit {
        commentContentEnrichmentTasks.values.forEach { $0.cancel() }
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard hasAppeared else {
            hasAppeared = true
            return
        }
        NodeSeekNotificationPrefetcher.shared.refreshNow()
    }

    @objc private func userInfoDidUpdate(_ notification: Notification) {
        guard displayMode == .content,
              selectedTab == .atMe || selectedTab == .reply else { return }
        tableView.reloadData()
    }

    @objc private func applicationDidBecomeActive() {
        guard isViewLoaded, view.window != nil else { return }
        NodeSeekNotificationPrefetcher.shared.refreshNow()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        configureNavigationItems()
        configureSegmentedControl()
        configureTableView()
        configureTabSwipeGestures()
        configureEmptyLabel()

        errorView.onRetry = { [weak self] in
            self?.refreshAllNotificationData(showLoadingForSelectedTab: true)
        }

        let segmentedContainer = UIView()
        segmentedContainer.translatesAutoresizingMaskIntoConstraints = false
        segmentedContainer.backgroundColor = .systemBackground
        segmentedContainer.addSubview(segmentedControl)

        view.addSubview(segmentedContainer)
        view.addSubview(tableView)
        view.addSubview(errorView)

        NSLayoutConstraint.activate([
            segmentedContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            segmentedContainer.heightAnchor.constraint(equalToConstant: 52),

            segmentedControl.leadingAnchor.constraint(equalTo: segmentedContainer.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: segmentedContainer.trailingAnchor, constant: -16),
            segmentedControl.centerYAnchor.constraint(equalTo: segmentedContainer.centerYAnchor),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: segmentedContainer.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])

        applyDisplayState()
    }

    private func configureNavigationItems() {
        let browserButton = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            style: .plain,
            target: self,
            action: #selector(openInBrowserTapped)
        )
        browserButton.accessibilityLabel = "在浏览器打开"
        self.browserButton = browserButton

        let markAllButton = UIBarButtonItem(
            title: "全部已读",
            style: .plain,
            target: self,
            action: #selector(markAllReadTapped)
        )
        markAllButton.accessibilityLabel = "全部标为已读"
        self.markAllButton = markAllButton

        navigationItem.rightBarButtonItems = [markAllButton, browserButton]
        updateMarkAllButton()
    }

    private func configureSegmentedControl() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedTab = selectedTab
        segmentedControl.onSelectionChanged = { [weak self] tab in
            self?.selectTab(tab)
        }
        updateSegmentTitles()
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 82
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(NotificationMentionCell.self, forCellReuseIdentifier: NotificationMentionCell.reuseIdentifier)
        tableView.register(NotificationMessageCell.self, forCellReuseIdentifier: NotificationMessageCell.reuseIdentifier)
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    private func configureTabSwipeGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(tabPanRecognized(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = true
        pan.delegate = self
        tableView.addGestureRecognizer(pan)
        tableView.panGestureRecognizer.require(toFail: pan)
        tabSwipePanGesture = pan
    }

    private func configureEmptyLabel() {
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.numberOfLines = 0
    }

    private func loadInitialNotificationData() {
        Task { [weak self] in
            guard let self else { return }
            currentUserID = await currentAccountStore.snapshot()?.account.nodeSeekUID
            restoreCachedNotificationDataIfAvailable()
            if loadedTabs.contains(selectedTab) {
                displayMode = .content
                applyDisplayState()
                tableView.reloadData()
                updateSegmentTitles()
                updateMarkAllButton()
                loadUnreadCount(publishUpdate: true)
                // 缓存秒开路径同样立即补全被@/回复内容，不等网络刷新完成，
                // 否则网络缓慢时可见行长时间没有正文预览。
                if selectedTab == .atMe || selectedTab == .reply {
                    enrichMissingCommentContent(for: selectedTab)
                }
                refreshAllNotificationData()
                return
            }
            // 缓存尚未写入时，用户已主动打开消息页，应立即请求当前 @我 首屏；
            // 全局预取仍在后台补齐回复主题和私信，避免为了去重牺牲首次点击速度。
            NodeSeekNotificationPrefetcher.shared.resumeAfterForegroundActivationIfReady()
            loadUnreadCount(publishUpdate: true)
            loadSelectedTab(showLoading: true)
        }
    }

    @objc private func notificationCacheDidUpdate(_ notification: Notification) {
        guard let ownerID = NodeSeekNotificationCacheEvent.ownerID(from: notification),
              ownerID == currentUserID else {
            return
        }
        applyPrefetchedCacheIfAvailable()
    }

    private func loadUnreadCount(
        publishUpdate: Bool = false,
        postReadStateChangeOnFailure: Bool = false
    ) {
        Task { [weak self] in
            guard let self else { return }
            await refreshUnreadCount(
                publishUpdate: publishUpdate,
                postReadStateChangeOnFailure: postReadStateChangeOnFailure
            )
        }
    }

    private func refreshUnreadCount(
        publishUpdate: Bool,
        postReadStateChangeOnFailure: Bool
    ) async {
        do {
            let loadedUnreadCount = try await client.loadUnreadCount()
            unreadCount = reconciledUnreadCount(from: loadedUnreadCount)
            unreadCount = NodeSeekNotificationMemoryCache.shared.store(
                unreadCount: unreadCount,
                ownerID: currentUserID
            ) ?? unreadCount
            updateSegmentTitles()
            updateMarkAllButton()
            if publishUpdate {
                NodeSeekNotificationUnreadCountEvent.post(unreadCount)
            }
        } catch {
            if postReadStateChangeOnFailure {
                postNotificationReadStateChange()
            }
            AppLog.debug(.account, "通知未读数加载失败: \(error.localizedDescription)")
        }
    }

    private func refreshUnreadCountAfterReadStateChange() {
        markCurrentAccountNotificationStateStale()
        loadUnreadCount(
            publishUpdate: true,
            postReadStateChangeOnFailure: true
        )
    }

    private func loadSelectedTab(showLoading: Bool) {
        loadTab(selectedTab, showLoading: showLoading)
    }

    private func loadTab(
        _ tab: NodeSeekNotificationTab,
        showLoading: Bool,
        retryAttempt: Int = 0
    ) {
        guard loadingTabs.contains(tab) == false else { return }
        cancelCommentContentEnrichment(for: tab)
        loadingTabs.insert(tab)
        let token = tabLoadTokens[tab, default: 0] + 1
        tabLoadTokens[tab] = token
        let wasLoaded = loadedTabs.contains(tab)
        if showLoading, tab == selectedTab, wasLoaded == false {
            displayMode = .loading
            applyDisplayState()
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await loadPayload(for: tab)
                applyLoadedPayload(payload, to: tab, token: token)
            } catch {
                loadingTabs.remove(tab)
                if retryAttempt == 0, Self.isTemporaryServerError(error) {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard Task.isCancelled == false else { return }
                    self.loadTab(tab, showLoading: false, retryAttempt: 1)
                    return
                }
                showError(error.localizedDescription, tab: tab, token: token)
                completeInitialAtMeLoadIfNeeded(tab: tab)
                performPendingRefreshIfNeeded(for: tab)
            }
        }
    }

    private func loadPayload(for tab: NodeSeekNotificationTab) async throws -> NotificationTabPayload {
        switch tab {
        case .atMe:
            return .notifications(try await client.loadAtMe())
        case .reply:
            return .notifications(try await client.loadReplies())
        case .message:
            async let loadedRecords = client.loadMessageConversations()
            async let accountSnapshot = currentAccountStore.snapshot()
            let records = try await loadedRecords
            let snapshot = await accountSnapshot
            let resolvedCurrentUserID = snapshot?.account.nodeSeekUID ?? currentUserID
            currentUserID = resolvedCurrentUserID
            cacheCurrentNotificationData()
            return .messages(
                NodeSeekMessageConversationRecord.latestConversations(
                    from: records,
                    currentUserID: resolvedCurrentUserID
                )
            )
        }
    }

    private func applyLoadedPayload(
        _ payload: NotificationTabPayload,
        to tab: NodeSeekNotificationTab,
        token: Int
    ) {
        guard tabLoadTokens[tab] == token else { return }
        loadingTabs.remove(tab)
        let wasLoaded = loadedTabs.contains(tab)

        let newRecordIDs: [Int]
        switch payload {
        case .notifications(let records):
            let previousRecords = notificationRecords(for: tab)
            let mergedRecords = mergeNotificationRecords(records, for: tab, preserving: previousRecords)
            newRecordIDs = wasLoaded ? newlyArrivedIDs(in: mergedRecords, comparedWith: previousRecords) : []
            setNotificationRecords(mergedRecords, for: tab)
            NodeSeekNotificationMemoryCache.shared.store(
                records: mergedRecords,
                for: tab,
                ownerID: currentUserID
            )
        case .messages(let records):
            let mergedRecords = mergeMessageRecords(records, preserving: messageRecords)
            newRecordIDs = wasLoaded ? newlyArrivedMessageIDs(in: mergedRecords, comparedWith: messageRecords) : []
            messageRecords = mergedRecords
            NodeSeekNotificationMemoryCache.shared.store(
                messageRecords: mergedRecords,
                ownerID: currentUserID
            )
        }

        loadedTabs.insert(tab)
        reconcileUnreadCountUsingLoadedRecords()
        if newRecordIDs.isEmpty == false {
            queueIncomingStream(for: newRecordIDs, tab: tab)
            loadUnreadCount(publishUpdate: true)
        }
        if tab == .atMe || tab == .reply {
            enrichMissingCommentContent(for: tab)
        }
        let hasPendingRefresh = pendingRefreshTabs.contains(tab)
        let shouldReplayContentAppearance = wasLoaded == false
            || refreshFeedbackTab == tab
            || refreshControl.isRefreshing
        finishLoading(
            tab: tab,
            restoresContentOffset: wasLoaded == false,
            endsRefreshFeedback: hasPendingRefresh == false,
            shouldReplayContentAppearance: shouldReplayContentAppearance
        )
        completeInitialAtMeLoadIfNeeded(tab: tab)
        performPendingRefreshIfNeeded(for: tab)
    }

    private func finishLoading(
        tab: NodeSeekNotificationTab,
        restoresContentOffset: Bool,
        endsRefreshFeedback: Bool,
        shouldReplayContentAppearance: Bool
    ) {
        guard tab == selectedTab else { return }
        if endsRefreshFeedback {
            refreshControl.endRefreshing()
            refreshFeedbackTab = nil
        }
        displayMode = .content
        errorView.isHidden = true
        applyDisplayState()
        UIView.performWithoutAnimation {
            resetVisibleStreamAppearance()
            tableView.reloadData()
            tableView.layoutIfNeeded()
        }
        if restoresContentOffset {
            restoreContentOffset(for: tab)
        }
        updateMarkAllButton()
        presentVisibleContentAppearance(forceReplay: shouldReplayContentAppearance)
        scheduleVisibleRecordsAsRead()
    }

    private func prefetchInactiveTabs(forceRefresh: Bool = false) {
        for tab in NodeSeekNotificationTab.allCases
            where tab != selectedTab && (forceRefresh || loadedTabs.contains(tab) == false)
        {
            requestRefresh(for: tab, showLoading: false)
        }
    }

    /// 首屏先完成 @我 的首轮请求，避免与三个通知接口并发时延后最先可见的内容。
    private func completeInitialAtMeLoadIfNeeded(tab: NodeSeekNotificationTab) {
        guard tab == .atMe, hasCompletedInitialAtMeLoad == false else { return }
        hasCompletedInitialAtMeLoad = true
        prefetchInactiveTabs(forceRefresh: true)
    }

    private func refreshAllNotificationData(showLoadingForSelectedTab: Bool = false) {
        loadUnreadCount(publishUpdate: true)
        guard hasCompletedInitialAtMeLoad else {
            loadTab(.atMe, showLoading: showLoadingForSelectedTab && selectedTab == .atMe)
            return
        }
        for tab in NodeSeekNotificationTab.allCases {
            requestRefresh(for: tab, showLoading: showLoadingForSelectedTab && tab == selectedTab)
        }
    }

    private func restoreCachedNotificationDataIfAvailable() {
        guard loadedTabs.isEmpty,
              let snapshot = NodeSeekNotificationMemoryCache.shared.snapshot(for: currentUserID) else {
            return
        }

        if let atMeRecords = snapshot.atMeRecords {
            self.atMeRecords = atMeRecords
            loadedTabs.insert(.atMe)
        }
        if let replyRecords = snapshot.replyRecords {
            self.replyRecords = replyRecords
            loadedTabs.insert(.reply)
        }
        if let messageRecords = snapshot.messageRecords {
            self.messageRecords = messageRecords
            loadedTabs.insert(.message)
        }
        if let unreadCount = snapshot.unreadCount {
            self.unreadCount = unreadCount
        }
        hasCompletedInitialAtMeLoad = loadedTabs.contains(.atMe)

        updateSegmentTitles()
        updateMarkAllButton()
        guard loadedTabs.contains(selectedTab) else { return }
        displayMode = .content
        applyDisplayState()
        UIView.performWithoutAnimation {
            resetVisibleStreamAppearance()
            tableView.reloadData()
            tableView.layoutIfNeeded()
        }
    }

    private func applyPrefetchedCacheIfAvailable() {
        guard let snapshot = NodeSeekNotificationMemoryCache.shared.snapshot(for: currentUserID) else {
            return
        }

        var selectedTabChanged = false

        if let incomingRecords = snapshot.atMeRecords {
            let previousRecords = atMeRecords
            let mergedRecords = mergeNotificationRecords(incomingRecords, for: .atMe, preserving: previousRecords)
            if mergedRecords != previousRecords {
                if loadedTabs.contains(.atMe) {
                    queueIncomingStream(
                        for: newlyArrivedIDs(in: mergedRecords, comparedWith: previousRecords)
                            + newlyResolvedContentIDs(in: mergedRecords, comparedWith: previousRecords),
                        tab: .atMe
                    )
                }
                atMeRecords = mergedRecords
                selectedTabChanged = selectedTab == .atMe
            }
            loadedTabs.insert(.atMe)
            hasCompletedInitialAtMeLoad = true
            if selectedTab == .atMe {
                enrichMissingCommentContent(for: .atMe)
            }
        }

        if let incomingRecords = snapshot.replyRecords {
            let previousRecords = replyRecords
            let mergedRecords = mergeNotificationRecords(incomingRecords, for: .reply, preserving: previousRecords)
            if mergedRecords != previousRecords {
                if loadedTabs.contains(.reply) {
                    queueIncomingStream(
                        for: newlyArrivedIDs(in: mergedRecords, comparedWith: previousRecords)
                            + newlyResolvedContentIDs(in: mergedRecords, comparedWith: previousRecords),
                        tab: .reply
                    )
                }
                replyRecords = mergedRecords
                selectedTabChanged = selectedTab == .reply
            }
            loadedTabs.insert(.reply)
            if selectedTab == .reply {
                enrichMissingCommentContent(for: .reply)
            }
        }

        if let incomingRecords = snapshot.messageRecords {
            let previousRecords = messageRecords
            let mergedRecords = mergeMessageRecords(incomingRecords, preserving: previousRecords)
            if mergedRecords != previousRecords {
                if loadedTabs.contains(.message) {
                    queueIncomingStream(
                        for: newlyArrivedMessageIDs(in: mergedRecords, comparedWith: previousRecords),
                        tab: .message
                    )
                }
                messageRecords = mergedRecords
                selectedTabChanged = selectedTab == .message
            }
            loadedTabs.insert(.message)
        }

        if let incomingUnreadCount = snapshot.unreadCount {
            unreadCount = incomingUnreadCount
        }
        reconcileUnreadCountUsingLoadedRecords()

        guard selectedTabChanged || (displayMode != .content && loadedTabs.contains(selectedTab)) else {
            return
        }
        displayMode = .content
        applyDisplayState()
        UIView.performWithoutAnimation {
            resetVisibleStreamAppearance()
            tableView.reloadData()
            tableView.layoutIfNeeded()
        }
        presentVisibleContentAppearance()
        scheduleVisibleRecordsAsRead()
    }

    private func notificationRecords(for tab: NodeSeekNotificationTab) -> [NodeSeekNotificationRecord] {
        switch tab {
        case .atMe:
            return atMeRecords
        case .reply:
            return replyRecords
        case .message:
            return []
        }
    }

    private func setNotificationRecords(_ records: [NodeSeekNotificationRecord], for tab: NodeSeekNotificationTab) {
        switch tab {
        case .atMe:
            atMeRecords = records
        case .reply:
            replyRecords = records
        case .message:
            break
        }
    }

    private func mergeNotificationRecords(
        _ incomingRecords: [NodeSeekNotificationRecord],
        for tab: NodeSeekNotificationTab,
        preserving existingRecords: [NodeSeekNotificationRecord]
    ) -> [NodeSeekNotificationRecord] {
        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        let persistedReadState = NodeSeekNotificationReadStateStore.shared
        return incomingRecords.map { incomingRecord in
            guard let existingRecord = existingByID[incomingRecord.id] else {
                var record = incomingRecord
                if persistedReadState.isViewed(id: record.id, tab: tab, ownerID: currentUserID) {
                    record.markViewed()
                }
                return record
            }
            var mergedRecord = incomingRecord
            if mergedRecord.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                mergedRecord.content = existingRecord.content
                mergedRecord.resolvedCommentPage = existingRecord.resolvedCommentPage
            }
            if existingRecord.isViewed || persistedReadState.isViewed(id: incomingRecord.id, tab: tab, ownerID: currentUserID) {
                mergedRecord.viewed = 1
            }
            return mergedRecord
        }
    }

    private func mergeMessageRecords(
        _ incomingRecords: [NodeSeekMessageConversationRecord],
        preserving existingRecords: [NodeSeekMessageConversationRecord]
    ) -> [NodeSeekMessageConversationRecord] {
        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.maxID, $0) })
        let persistedReadState = NodeSeekNotificationReadStateStore.shared
        return incomingRecords.map { incomingRecord in
            guard let existingRecord = existingByID[incomingRecord.maxID], existingRecord.isViewed else {
                var record = incomingRecord
                if persistedReadState.isViewed(id: record.maxID, tab: .message, ownerID: currentUserID) {
                    record.markViewed()
                }
                return record
            }
            var mergedRecord = incomingRecord
            mergedRecord.viewed = 1
            return mergedRecord
        }
    }

    private func reconciledUnreadCount(from remoteCount: NodeSeekNotificationUnreadCount) -> NodeSeekNotificationUnreadCount {
        var reconciled = remoteCount
        if loadedTabs.contains(.atMe) {
            reconciled.setCount(atMeRecords.reduce(0) { partial, record in
                partial + (record.isViewed ? 0 : record.displayUnreadCount)
            }, for: .atMe)
        }
        if loadedTabs.contains(.reply) {
            reconciled.setCount(replyRecords.reduce(0) { partial, record in
                partial + (record.isViewed ? 0 : record.displayUnreadCount)
            }, for: .reply)
        }
        if loadedTabs.contains(.message) {
            reconciled.setCount(messageRecords.reduce(0) { partial, record in
                partial + (record.isViewed ? 0 : record.displayUnreadCount)
            }, for: .message)
        }
        return reconciled
    }

    private func reconcileUnreadCountUsingLoadedRecords() {
        unreadCount = reconciledUnreadCount(from: unreadCount)
        cacheCurrentNotificationData()
        updateSegmentTitles()
        updateMarkAllButton()
    }

    private func newlyArrivedIDs(
        in incomingRecords: [NodeSeekNotificationRecord],
        comparedWith existingRecords: [NodeSeekNotificationRecord]
    ) -> [Int] {
        let existingIDs = Set(existingRecords.map(\.id))
        return incomingRecords.map(\.id).filter { existingIDs.contains($0) == false }
    }

    private func newlyResolvedContentIDs(
        in incomingRecords: [NodeSeekNotificationRecord],
        comparedWith existingRecords: [NodeSeekNotificationRecord]
    ) -> [Int] {
        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        return incomingRecords.compactMap { record in
            guard let existingRecord = existingByID[record.id],
                  existingRecord.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                  record.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return record.id
        }
    }

    private func newlyArrivedMessageIDs(
        in incomingRecords: [NodeSeekMessageConversationRecord],
        comparedWith existingRecords: [NodeSeekMessageConversationRecord]
    ) -> [Int] {
        let existingIDs = Set(existingRecords.map(\.maxID))
        return incomingRecords.map(\.maxID).filter { existingIDs.contains($0) == false }
    }

    private func queueIncomingStream(for recordIDs: [Int], tab: NodeSeekNotificationTab) {
        let limitedIDs = recordIDs.prefix(Self.maximumStreamedNewRowCount)
        guard limitedIDs.isEmpty == false else { return }
        pendingStreamRecordIDs[tab, default: []].formUnion(limitedIDs)
    }

    private func streamVisibleIncomingRowsIfNeeded() {
        guard displayMode == .content,
              pendingStreamRecordIDs[selectedTab]?.isEmpty == false else {
            return
        }
        let visibleRows = (tableView.indexPathsForVisibleRows ?? []).sorted { $0.row < $1.row }
        for (sequence, indexPath) in visibleRows.enumerated() {
            guard let cell = tableView.cellForRow(at: indexPath) else { continue }
            streamIncomingRowIfNeeded(cell, at: indexPath, sequence: sequence)
        }
    }

    /// 切换一级 Tab 或主动刷新时只动画当前可见行，不先清空 table，避免旧版本的闪屏。
    private func presentVisibleContentAppearance(forceReplay: Bool = false) {
        guard displayMode == .content else { return }
        if forceReplay {
            pendingStreamRecordIDs[selectedTab] = []
            replayVisibleContentAppearance()
            return
        }
        streamVisibleIncomingRowsIfNeeded()
    }

    private func replayVisibleContentAppearance() {
        guard displayMode == .content else { return }
        let cells = tableView.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        for (index, cell) in cells.enumerated() {
            cell.layer.removeAllAnimations()
            cell.alpha = 0
            cell.transform = CGAffineTransform(translationX: 0, y: 12)
            UIView.animate(
                withDuration: 0.30,
                delay: Double(min(index, 8)) * 0.035,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                cell.alpha = 1
                cell.transform = .identity
            }
        }
    }

    private func streamIncomingRowIfNeeded(
        _ cell: UITableViewCell,
        at indexPath: IndexPath,
        sequence: Int
    ) {
        guard let recordID = recordID(at: indexPath, for: selectedTab),
              pendingStreamRecordIDs[selectedTab]?.remove(recordID) != nil else {
            return
        }
        cell.layer.removeAllAnimations()
        cell.alpha = 0
        cell.transform = CGAffineTransform(translationX: 0, y: 16)
        UIView.animate(
            withDuration: 0.34,
            delay: Double(min(sequence, 6)) * 0.055,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            cell.alpha = 1
            cell.transform = .identity
        }
    }

    private func resetVisibleStreamAppearance() {
        for cell in tableView.visibleCells {
            cell.layer.removeAllAnimations()
            cell.alpha = 1
            cell.transform = .identity
        }
    }

    private func recordID(at indexPath: IndexPath, for tab: NodeSeekNotificationTab) -> Int? {
        switch tab {
        case .atMe:
            guard atMeRecords.indices.contains(indexPath.row) else { return nil }
            return atMeRecords[indexPath.row].id
        case .reply:
            guard replyRecords.indices.contains(indexPath.row) else { return nil }
            return replyRecords[indexPath.row].id
        case .message:
            guard messageRecords.indices.contains(indexPath.row) else { return nil }
            return messageRecords[indexPath.row].maxID
        }
    }

    private func enrichMissingCommentContent(for tab: NodeSeekNotificationTab) {
        let candidates: [NodeSeekNotificationRecord]
        switch tab {
        case .atMe:
            candidates = atMeRecords
        case .reply:
            candidates = replyRecords
        case .message:
            return
        }
        let missingContent = Array(candidates.filter {
            $0.postID > 0 && ($0.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        }.prefix(Self.maximumCommentContentEnrichmentRecords))
        guard missingContent.isEmpty == false else {
            cancelCommentContentEnrichment(for: tab)
            return
        }

        cancelCommentContentEnrichment(for: tab)
        let token = commentContentEnrichmentTokens[tab, default: 0]
        let maximumConcurrentLoads = Self.maxConcurrentCommentContentLoads
        commentContentEnrichmentTasks[tab] = Task { [weak self, missingContent, maximumConcurrentLoads] in
            await withTaskGroup(of: (Int, NodeSeekNotificationContentResolver.ResolvedContent?).self) { group in
                var nextIndex = 0
                let initialTaskCount = min(maximumConcurrentLoads, missingContent.count)

                for _ in 0..<initialTaskCount {
                    let record = missingContent[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let content = await NodeSeekNotificationContentResolver.shared.resolveContent(for: record)
                        return (record.id, content)
                    }
                }

                while let (recordID, result) = await group.next() {
                    guard Task.isCancelled == false else {
                        group.cancelAll()
                        return
                    }

                    if let result,
                       result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        await self?.applyResolvedCommentContent(
                            result,
                            forRecordID: recordID,
                            to: tab,
                            token: token
                        )
                    }

                    guard nextIndex < missingContent.count else { continue }
                    let record = missingContent[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let content = await NodeSeekNotificationContentResolver.shared.resolveContent(for: record)
                        return (record.id, content)
                    }
                }
            }
            await self?.finishCommentContentEnrichment(for: tab, token: token)
        }
    }

    private func applyResolvedCommentContent(
        _ result: NodeSeekNotificationContentResolver.ResolvedContent,
        forRecordID recordID: Int,
        to tab: NodeSeekNotificationTab,
        token: Int
    ) {
        guard commentContentEnrichmentTokens[tab] == token else { return }

        let changedRow: IndexPath?
        switch tab {
        case .atMe:
            guard let index = atMeRecords.firstIndex(where: { $0.id == recordID }),
                  atMeRecords[index].content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                return
            }
            atMeRecords[index].content = result.content
            atMeRecords[index].resolvedCommentPage = result.page
            NodeSeekNotificationMemoryCache.shared.store(
                records: atMeRecords,
                for: .atMe,
                ownerID: currentUserID
            )
            changedRow = IndexPath(row: index, section: 0)
        case .reply:
            guard let index = replyRecords.firstIndex(where: { $0.id == recordID }),
                  replyRecords[index].content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                return
            }
            replyRecords[index].content = result.content
            replyRecords[index].resolvedCommentPage = result.page
            NodeSeekNotificationMemoryCache.shared.store(
                records: replyRecords,
                for: .reply,
                ownerID: currentUserID
            )
            changedRow = IndexPath(row: index, section: 0)
        case .message:
            return
        }

        guard selectedTab == tab,
              displayMode == .content,
              let changedRow,
              changedRow.row < currentRecordCount else { return }
        tableView.reloadRows(at: [changedRow], with: .none)
    }

    private func cancelCommentContentEnrichment(for tab: NodeSeekNotificationTab) {
        commentContentEnrichmentTokens[tab, default: 0] += 1
        commentContentEnrichmentTasks[tab]?.cancel()
        commentContentEnrichmentTasks[tab] = nil
    }

    private func finishCommentContentEnrichment(for tab: NodeSeekNotificationTab, token: Int) {
        guard commentContentEnrichmentTokens[tab] == token else { return }
        commentContentEnrichmentTasks[tab] = nil
    }

    private func showError(_ message: String, tab: NodeSeekNotificationTab, token: Int) {
        guard tabLoadTokens[tab] == token, tab == selectedTab else { return }
        refreshControl.endRefreshing()
        if loadedTabs.contains(tab) {
            // Keep prior tab data visible when the service has a brief 503 outage.
            displayMode = .content
            errorView.isHidden = true
            applyDisplayState()
            return
        }
        displayMode = .error
        errorView.messageLabel.text = message
        applyDisplayState()
    }

    private static func isTemporaryServerError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("503") || message.contains("service unavailable")
    }

    private func applyDisplayState() {
        switch displayMode {
        case .content:
            errorView.isHidden = true
            loadingView.stopAnimating()
            tableView.backgroundView = currentRecordCount == 0 ? emptyBackgroundView() : nil
        case .loading:
            errorView.isHidden = true
            loadingView.startAnimating()
            tableView.backgroundView = loadingView
        case .error:
            loadingView.stopAnimating()
            errorView.isHidden = false
            tableView.backgroundView = nil
        }
    }

    private func emptyBackgroundView() -> UIView {
        emptyLabel.text = emptyText(for: selectedTab)
        return emptyLabel
    }

    private func emptyText(for tab: NodeSeekNotificationTab) -> String {
        switch tab {
        case .atMe:
            return "没有@消息"
        case .reply:
            return "没有新的评论"
        case .message:
            return "没有私信"
        }
    }

    private func updateSegmentTitles() {
        segmentedControl.setUnreadCount(unreadCount)
    }

    private func updateMarkAllButton() {
        markAllButton?.isEnabled = hasUnreadNotifications
    }

    private var hasUnreadNotifications: Bool {
        unreadCount.all > 0
            || atMeRecords.contains(where: { !$0.isViewed })
            || replyRecords.contains(where: { !$0.isViewed })
            || messageRecords.contains(where: { !$0.isViewed })
    }

    private var currentRecordCount: Int {
        switch selectedTab {
        case .atMe:
            return atMeRecords.count
        case .reply:
            return replyRecords.count
        case .message:
            return messageRecords.count
        }
    }

    @objc private func tabPanRecognized(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            suppressRowSelectionUntil = Date().addingTimeInterval(0.35)
            let translation = recognizer.translation(in: tableView)
            let limitedTranslation = max(-24, min(24, translation.x * 0.16))
            tableView.transform = CGAffineTransform(translationX: limitedTranslation, y: 0)
            return
        case .ended:
            break
        case .cancelled, .failed, .possible:
            suppressRowSelectionUntil = Date().addingTimeInterval(0.2)
            return
        @unknown default:
            return
        }

        let translation = recognizer.translation(in: tableView)
        let velocity = recognizer.velocity(in: tableView)
        let requiredDistance = min(tableView.bounds.width * 0.20, 72)
        guard abs(translation.x) >= requiredDistance || abs(velocity.x) >= 700 else {
            restoreTabSwipePosition()
            return
        }
        suppressRowSelectionUntil = Date().addingTimeInterval(0.35)
        let offset = translation.x < 0 ? 1 : -1
        let nextIndex = selectedTab.rawValue + offset
        guard let nextTab = NodeSeekNotificationTab(rawValue: nextIndex) else {
            restoreTabSwipePosition()
            return
        }
        animateTabSwipeTransition(to: nextTab, translationX: translation.x)
    }

    private func restoreTabSwipePosition() {
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.tableView.transform = .identity
        }
    }

    private func animateTabSwipeTransition(to tab: NodeSeekNotificationTab, translationX: CGFloat) {
        let direction: CGFloat = translationX < 0 ? -1 : 1
        UIView.animate(
            withDuration: 0.10,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.tableView.transform = CGAffineTransform(translationX: direction * 12, y: 0)
        } completion: { [weak self] _ in
            guard let self else { return }
            UIView.animate(
                withDuration: 0.20,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.tableView.transform = .identity
            } completion: { _ in
                self.selectTab(tab)
            }
        }
    }

    private func selectTab(_ tab: NodeSeekNotificationTab) {
        guard tab != selectedTab else { return }
        tabContentOffsets[selectedTab] = tableView.contentOffset
        selectedTab = tab
        segmentedControl.selectedTab = tab
        updateMarkAllButton()
        if loadedTabs.contains(tab) {
            // 已加载 tab 立即本地呈现：无整表重建、无动画重播、无强制布局，
            // 消除“点击后要等一下才响应”的感知。网络刷新静默后台进行。
            displayMode = .content
            applyDisplayState()
            restoreContentOffset(for: tab)
            scheduleVisibleRecordsAsRead()
            requestRefresh(for: tab, showLoading: false)
        } else {
            loadSelectedTab(showLoading: true)
        }
    }

    private func restoreContentOffset(for tab: NodeSeekNotificationTab) {
        let fallback = CGPoint(x: 0, y: -tableView.adjustedContentInset.top)
        let offset = tabContentOffsets[tab] ?? fallback
        tableView.setContentOffset(offset, animated: false)
    }

    @objc private func refreshTriggered() {
        refreshCurrentNotificationData()
    }

    /// 双击消息 tab：重新拉取当前板块（@我/回复主题/私信）。
    func refreshFromDoubleTap() {
        showRefreshFeedback(for: selectedTab)
        refreshCurrentNotificationData()
    }

    /// 从其它一级功能区切回消息时刷新当前子标签；已有缓存先直接展示。
    func refreshFromTabSelection() {
        presentVisibleContentAppearance(forceReplay: true)
        refreshCurrentNotificationData()
    }

    private func refreshCurrentNotificationData() {
        loadUnreadCount(publishUpdate: true)
        requestRefresh(for: selectedTab, showLoading: false)
    }

    /// 只有用户实际停留在某个分栏并看见列表后才提交已读。预取、缓存写入和后台刷新都不会调用这里。
    private func scheduleVisibleRecordsAsRead() {
        let tab = selectedTab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            guard let self,
                  self.selectedTab == tab,
                  self.view.window != nil,
                  self.displayMode == .content else {
                return
            }
            self.markVisibleRecordsAsRead(in: tab)
        }
    }

    private func markVisibleRecordsAsRead(in tab: NodeSeekNotificationTab) {
        let visibleRows = (tableView.indexPathsForVisibleRows ?? []).map(\.row)
        guard visibleRows.isEmpty == false else { return }

        let ids: [Int]
        switch tab {
        case .atMe:
            ids = visibleRows.compactMap { row in
                guard atMeRecords.indices.contains(row), atMeRecords[row].isViewed == false else { return nil }
                atMeRecords[row].markViewed()
                return atMeRecords[row].id
            }
        case .reply:
            ids = visibleRows.compactMap { row in
                guard replyRecords.indices.contains(row), replyRecords[row].isViewed == false else { return nil }
                replyRecords[row].markViewed()
                return replyRecords[row].id
            }
        case .message:
            ids = visibleRows.compactMap { row in
                guard messageRecords.indices.contains(row), messageRecords[row].isViewed == false else { return nil }
                messageRecords[row].markViewed()
                return messageRecords[row].maxID
            }
        }
        guard ids.isEmpty == false else { return }

        NodeSeekNotificationReadStateStore.shared.markViewed(ids: ids, tab: tab, ownerID: currentUserID)
        unreadCount.decrement(for: tab, by: ids.count)
        cacheCurrentNotificationData()
        updateSegmentTitles()
        updateMarkAllButton()
        tableView.reloadData()

        Task { [weak self, ids, tab] in
            guard let self else { return }
            do {
                try await client.markViewed(ids: ids, tab: tab)
                refreshUnreadCountAfterReadStateChange()
            } catch {
                // 用户已实际读到内容，网络稍后恢复时继续由本地已读账本保持一致。
                AppLog.debug(.account, "通知已读同步延后: \(error.localizedDescription)")
            }
        }
    }

    private func requestRefresh(for tab: NodeSeekNotificationTab, showLoading: Bool) {
        guard loadingTabs.contains(tab) == false else {
            pendingRefreshTabs.insert(tab)
            return
        }
        loadTab(tab, showLoading: showLoading)
    }

    private func performPendingRefreshIfNeeded(for tab: NodeSeekNotificationTab) {
        guard pendingRefreshTabs.remove(tab) != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.requestRefresh(for: tab, showLoading: false)
        }
    }

    private func showRefreshFeedback(for tab: NodeSeekNotificationTab) {
        guard refreshControl.isRefreshing == false else { return }
        refreshFeedbackTab = tab
        refreshControl.beginRefreshing()
        let topOffset = -tableView.adjustedContentInset.top - max(refreshControl.bounds.height, 44)
        tableView.setContentOffset(CGPoint(x: 0, y: topOffset), animated: true)
    }

    @objc private func openInBrowserTapped() {
        openWebURL(selectedTab.webURL)
    }

    @objc private func markAllReadTapped() {
        guard hasUnreadNotifications else { return }
        let previousUnreadCount = unreadCount
        let previousAtMeRecords = atMeRecords
        let previousReplyRecords = replyRecords
        let previousMessageRecords = messageRecords

        markAllButton?.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                for tab in NodeSeekNotificationTab.allCases {
                    try await client.markAllViewed(tab: tab)
                }
                markAllLocally()
                refreshUnreadCountAfterReadStateChange()
            } catch {
                unreadCount = previousUnreadCount
                atMeRecords = previousAtMeRecords
                replyRecords = previousReplyRecords
                messageRecords = previousMessageRecords
                cacheCurrentNotificationData()
                updateSegmentTitles()
                updateMarkAllButton()
                tableView.reloadData()
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    private func markAllLocally() {
        atMeRecords = atMeRecords.map { record in
            var updated = record
            updated.markViewed()
            return updated
        }
        replyRecords = replyRecords.map { record in
            var updated = record
            updated.markViewed()
            return updated
        }
        messageRecords = messageRecords.map { record in
            var updated = record
            updated.markViewed()
            return updated
        }
        NodeSeekNotificationReadStateStore.shared.markViewed(
            ids: atMeRecords.map(\.id),
            tab: .atMe,
            ownerID: currentUserID
        )
        NodeSeekNotificationReadStateStore.shared.markViewed(
            ids: replyRecords.map(\.id),
            tab: .reply,
            ownerID: currentUserID
        )
        NodeSeekNotificationReadStateStore.shared.markViewed(
            ids: messageRecords.map(\.maxID),
            tab: .message,
            ownerID: currentUserID
        )
        unreadCount = .zero
        cacheCurrentNotificationData()
        updateSegmentTitles()
        updateMarkAllButton()
        tableView.reloadData()
    }

    private func markRead(
        id: Int,
        tab: NodeSeekNotificationTab,
        rollbackOnFailure: Bool,
        showFailure: Bool
    ) {
        let previousUnreadCount = unreadCount
        guard markRecordLocally(id: id, tab: tab) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.markViewed(ids: [id], tab: tab)
                refreshUnreadCountAfterReadStateChange()
            } catch {
                if rollbackOnFailure {
                    unmarkRecordLocally(id: id, tab: tab)
                    unreadCount = previousUnreadCount
                    cacheCurrentNotificationData()
                    updateSegmentTitles()
                    updateMarkAllButton()
                    if selectedTab == tab {
                        tableView.reloadData()
                    }
                } else {
                    loadUnreadCount()
                }
                if showFailure {
                    showErrorMessage(error.localizedDescription)
                }
            }
        }
    }

    @discardableResult
    private func markRecordLocally(id: Int, tab: NodeSeekNotificationTab) -> Bool {
        switch tab {
        case .atMe:
            guard let index = atMeRecords.firstIndex(where: { $0.id == id }),
                  atMeRecords[index].isViewed == false else {
                return false
            }
            atMeRecords[index].markViewed()
        case .reply:
            guard let index = replyRecords.firstIndex(where: { $0.id == id }),
                  replyRecords[index].isViewed == false else {
                return false
            }
            replyRecords[index].markViewed()
        case .message:
            guard let index = messageRecords.firstIndex(where: { $0.maxID == id }),
                  messageRecords[index].isViewed == false else {
                return false
            }
            messageRecords[index].markViewed()
        }

        unreadCount.decrement(for: tab)
        NodeSeekNotificationReadStateStore.shared.markViewed(ids: [id], tab: tab, ownerID: currentUserID)
        cacheCurrentNotificationData()
        updateSegmentTitles()
        updateMarkAllButton()
        if selectedTab == tab {
            tableView.reloadData()
        }
        return true
    }

    private func unmarkRecordLocally(id: Int, tab: NodeSeekNotificationTab) {
        switch tab {
        case .atMe:
            guard let index = atMeRecords.firstIndex(where: { $0.id == id }) else { return }
            atMeRecords[index].viewed = 0
        case .reply:
            guard let index = replyRecords.firstIndex(where: { $0.id == id }) else { return }
            replyRecords[index].viewed = 0
        case .message:
            guard let index = messageRecords.firstIndex(where: { $0.maxID == id }) else { return }
            messageRecords[index].viewed = 0
        }
        NodeSeekNotificationReadStateStore.shared.removeViewed(ids: [id], tab: tab, ownerID: currentUserID)
        cacheCurrentNotificationData()
    }

    private func openNotificationPost(_ record: NodeSeekNotificationRecord, tab: NodeSeekNotificationTab) {
        if record.isViewed == false {
            markRead(id: record.id, tab: tab, rollbackOnFailure: false, showFailure: false)
        }
        let detailViewController = PostDetailRouter.createModule(
            post: record.postSummary,
            page: 1
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func openNotificationReply(_ record: NodeSeekNotificationRecord, tab: NodeSeekNotificationTab) {
        if record.isViewed == false {
            markRead(id: record.id, tab: tab, rollbackOnFailure: false, showFailure: false)
        }
        let detailViewController = PostDetailRouter.createModule(
            post: record.postSummary,
            page: record.targetCommentPage,
            initialAnchorID: record.anchorID
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func openProfile(_ record: NodeSeekNotificationRecord) {
        navigationController?.pushViewController(
            ProfileTabViewController(userID: record.commenterID),
            animated: true
        )
    }

    private func openMessageConversation(_ record: NodeSeekMessageConversationRecord) {
        Task { [weak self] in
            guard let self else { return }
            let resolvedCurrentUserID: Int?
            if let currentUserID {
                resolvedCurrentUserID = currentUserID
            } else {
                resolvedCurrentUserID = await currentAccountStore.snapshot()?.account.nodeSeekUID
                currentUserID = resolvedCurrentUserID
            }
            guard let resolvedCurrentUserID else {
                showErrorMessage("登录后才能打开私信。")
                return
            }

            let participantID = record.participantID(currentUserID: resolvedCurrentUserID)
            guard participantID > 0, participantID != resolvedCurrentUserID else {
                showErrorMessage("无法识别私信会话对象，请刷新后重试。")
                return
            }
            if record.isViewed == false {
                markRead(id: record.maxID, tab: .message, rollbackOnFailure: false, showFailure: false)
            }
            navigationController?.pushViewController(
                PrivateMessageViewController(
                    participantID: participantID,
                    participantName: record.participantName(currentUserID: resolvedCurrentUserID)
                ),
                animated: true
            )
        }
    }

    private func openWebURL(_ url: URL) {
        if NodeSeekSite.isNodeSeekHost(url) {
            let viewController = NodeSeekWebViewController(url: url)
            navigationController?.pushViewController(viewController, animated: true)
            return
        }
        present(SFSafariViewController(url: url), animated: true)
    }

    private func showErrorMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func postNotificationReadStateChange() {
        NotificationCenter.default.post(name: .nodeSeekNotificationReadStateDidChange, object: nil)
    }

    private func markCurrentAccountNotificationStateStale() {
        Task { [currentAccountStore] in
            await currentAccountStore.markStale()
        }
    }

    private func cacheCurrentNotificationData() {
        if loadedTabs.contains(.atMe) {
            NodeSeekNotificationMemoryCache.shared.store(
                records: atMeRecords,
                for: .atMe,
                ownerID: currentUserID
            )
        }
        if loadedTabs.contains(.reply) {
            NodeSeekNotificationMemoryCache.shared.store(
                records: replyRecords,
                for: .reply,
                ownerID: currentUserID
            )
        }
        if loadedTabs.contains(.message) {
            NodeSeekNotificationMemoryCache.shared.store(
                messageRecords: messageRecords,
                ownerID: currentUserID
            )
        }
        NodeSeekNotificationMemoryCache.shared.store(
            unreadCount: unreadCount,
            ownerID: currentUserID
        )
    }
}

extension NotificationViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayMode == .content else { return 0 }
        return currentRecordCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch selectedTab {
        case .atMe:
            let record = atMeRecords[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NotificationMentionCell.reuseIdentifier,
                for: indexPath
            ) as? NotificationMentionCell ?? NotificationMentionCell()
            cell.configure(
                record: record,
                tab: .atMe,
                timeText: NodeSeekNotificationDateParser.displayText(from: record.createdAt),
                onProfileTapped: { [weak self] in self?.openProfile(record) },
                onMarkReadTapped: { [weak self] in
                    self?.markRead(id: record.id, tab: .atMe, rollbackOnFailure: true, showFailure: true)
                },
                onTitleTapped: { [weak self] in
                    self?.openNotificationPost(record, tab: .atMe)
                },
                onReplyTapped: { [weak self] in
                    self?.openNotificationReply(record, tab: .atMe)
                }
            )
            return cell
        case .reply:
            let record = replyRecords[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NotificationMentionCell.reuseIdentifier,
                for: indexPath
            ) as? NotificationMentionCell ?? NotificationMentionCell()
            cell.configure(
                record: record,
                tab: .reply,
                timeText: NodeSeekNotificationDateParser.displayText(from: record.createdAt),
                onProfileTapped: { [weak self] in self?.openProfile(record) },
                onMarkReadTapped: { [weak self] in
                    self?.markRead(id: record.id, tab: .reply, rollbackOnFailure: true, showFailure: true)
                },
                onTitleTapped: { [weak self] in
                    self?.openNotificationPost(record, tab: .reply)
                },
                onReplyTapped: { [weak self] in
                    self?.openNotificationReply(record, tab: .reply)
                }
            )
            return cell
        case .message:
            let record = messageRecords[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NotificationMessageCell.reuseIdentifier,
                for: indexPath
            ) as? NotificationMessageCell ?? NotificationMessageCell()
            cell.configure(
                record: record,
                currentUserID: currentUserID,
                timeText: NodeSeekNotificationDateParser.displayText(from: record.createdAt)
            )
            return cell
        }
    }
}

extension NotificationViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === tabSwipePanGesture,
              let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        let velocity = panGestureRecognizer.velocity(in: tableView)
        return abs(velocity.x) > max(abs(velocity.y) * 1.25, 55)
    }
}

extension NotificationViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        streamIncomingRowIfNeeded(cell, at: indexPath, sequence: 0)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard displayMode == .content, Date() >= suppressRowSelectionUntil else { return }
        switch selectedTab {
        case .atMe:
            guard atMeRecords.indices.contains(indexPath.row) else { return }
            openNotificationReply(atMeRecords[indexPath.row], tab: .atMe)
        case .reply:
            guard replyRecords.indices.contains(indexPath.row) else { return }
            openNotificationReply(replyRecords[indexPath.row], tab: .reply)
        case .message:
            guard messageRecords.indices.contains(indexPath.row) else { return }
            openMessageConversation(messageRecords[indexPath.row])
        }
    }
}

private final class NotificationLoadingView: UIView {
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground

        label.text = "加载中"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [indicator, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimating() {
        indicator.startAnimating()
    }

    func stopAnimating() {
        indicator.stopAnimating()
    }
}

/// UISegmentedControl 不支持给标题中的数字单独设色；通知分栏使用轻量自定义控件，
/// 保持系统分段交互，同时让未读数始终为红色且 0 不占位。
private final class NotificationTabSegmentedControl: UIView {
    var selectedTab: NodeSeekNotificationTab = .atMe {
        didSet { updateSelectionAppearance() }
    }
    var onSelectionChanged: ((NodeSeekNotificationTab) -> Void)?

    private var titleLabels: [NodeSeekNotificationTab: UILabel] = [:]
    private var countLabels: [NodeSeekNotificationTab: UILabel] = [:]
    private var buttons: [NodeSeekNotificationTab: UIControl] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 0
        addSubview(stack)

        for tab in NodeSeekNotificationTab.allCases {
            let item = makeItem(for: tab)
            stack.addArrangedSubview(item)
            buttons[tab] = item
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
        updateSelectionAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUnreadCount(_ unreadCount: NodeSeekNotificationUnreadCount) {
        for tab in NodeSeekNotificationTab.allCases {
            let value = unreadCount.count(for: tab)
            countLabels[tab]?.text = value > 0 ? "\(value)" : nil
            countLabels[tab]?.isHidden = value == 0
            buttons[tab]?.accessibilityLabel = value > 0 ? "\(tab.title)，\(value) 条未读" : tab.title
        }
    }

    private func makeItem(for tab: NodeSeekNotificationTab) -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.tag = tab.rawValue
        control.layer.cornerRadius = 6
        control.layer.cornerCurve = .continuous
        control.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)

        let title = UILabel()
        title.text = tab.title
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.adjustsFontForContentSizeCategory = true
        title.setContentHuggingPriority(.required, for: .horizontal)
        titleLabels[tab] = title

        let count = UILabel()
        count.font = .preferredFont(forTextStyle: .caption1)
        count.textColor = .systemRed
        count.adjustsFontForContentSizeCategory = true
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.isHidden = true
        countLabels[tab] = count

        let content = UIStackView(arrangedSubviews: [title, count])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 3
        control.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: control.leadingAnchor, constant: 6),
            content.trailingAnchor.constraint(lessThanOrEqualTo: control.trailingAnchor, constant: -6)
        ])
        return control
    }

    private func updateSelectionAppearance() {
        for tab in NodeSeekNotificationTab.allCases {
            let selected = tab == selectedTab
            buttons[tab]?.backgroundColor = selected ? .systemBackground : .clear
            titleLabels[tab]?.textColor = selected ? .label : .secondaryLabel
            titleLabels[tab]?.font = selected
                ? .preferredFont(forTextStyle: .headline)
                : .preferredFont(forTextStyle: .subheadline)
        }
    }

    @objc private func tabTapped(_ sender: UIControl) {
        guard let tab = NodeSeekNotificationTab(rawValue: sender.tag), tab != selectedTab else { return }
        selectedTab = tab
        onSelectionChanged?(tab)
    }
}
