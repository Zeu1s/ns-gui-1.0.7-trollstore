//
//  FansListViewController.swift
//  nodeseek
//

import UIKit
import Kanna

struct FansListEntry: Equatable {
    let userID: Int?
    let name: String
    let avatarURL: URL?
    let metaText: String?
}

/// 粉丝/关注列表原生页：加载用户空间对应 hash 路由后解析成员列表。
/// HTTP 首选；SPA 渲染形态由 WebView 回退兜底。
final class FansListViewController: UIViewController {
    private enum ListKind {
        case fans
        case follows

        var title: String { self == .fans ? "粉丝" : "关注" }
        var hashRoute: String { self == .fans ? "#/fans" : "#/follows" }
    }

    private var kind: ListKind
    private let uid: Int
    private let isSelfProfile: Bool

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let kindSegmentedControl = UISegmentedControl(items: ["我的粉丝", "我关注的人"])
    private let refreshControl = UIRefreshControl()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()

    private var entries: [FansListEntry] = []
    private var displayMode: DisplayMode = .loading

    private enum DisplayMode {
        case content
        case loading
        case error
    }

    private init(kind: ListKind, uid: Int, isSelfProfile: Bool) {
        self.kind = kind
        self.uid = uid
        self.isSelfProfile = isSelfProfile
        super.init(nibName: nil, bundle: nil)
        title = "\(kind.title)列表"
    }

    convenience init(fansOf uid: Int, isSelfProfile: Bool = false) {
        self.init(kind: .fans, uid: uid, isSelfProfile: isSelfProfile)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureTableView()
        reload()
    }

    private func configureTableView() {
        view.backgroundColor = .systemGroupedBackground

        // 与 PWA 一致的双分类：我的粉丝 / 我关注的人。
        kindSegmentedControl.selectedSegmentIndex = kind == .fans ? 0 : 1
        kindSegmentedControl.addTarget(self, action: #selector(kindChanged), for: .valueChanged)
        kindSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(kindSegmentedControl)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.rowHeight = 60
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl

        errorLabel.font = .preferredFont(forTextStyle: .subheadline)
        errorLabel.textColor = .secondaryLabel
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            kindSegmentedControl.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            kindSegmentedControl.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            kindSegmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: kindSegmentedControl.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc
    private func kindChanged() {
        let newKind: ListKind = kindSegmentedControl.selectedSegmentIndex == 0 ? .fans : .follows
        guard newKind != kind else { return }
        kind = newKind
        entries = []
        title = "\(newKind.title)列表"
        reload()
    }

    @objc private func refreshTriggered() {
        reload()
    }

    private func reload() {
        displayMode = entries.isEmpty ? .loading : .content
        applyDisplayState()
        Task { [weak self] in
            guard let self else { return }
            let loaded = await Self.fetchEntries(
                kind: self.kind,
                uid: self.uid,
                isSelfProfile: self.isSelfProfile
            )
            guard self.isViewLoaded else { return }
            self.entries = loaded
            self.refreshControl.endRefreshing()
            if loaded.isEmpty && self.entries.isEmpty == false {
                self.displayMode = .content
            } else if loaded.isEmpty {
                self.displayMode = .error
                self.errorLabel.text = "暂无\(self.kind.title)（或页面渲染失败，下拉重试）"
            } else {
                self.displayMode = .content
            }
            self.applyDisplayState()
            self.tableView.reloadData()
        }
    }

    /// 站点真实路由：自己的粉丝列表是独立页面 /fans?type=fans；
    /// 其余（他人粉丝、关注列表）在空间页 hash 路由 #/fans、#/follows。
    /// 此前 WebView 统一加载 /space/{uid} 概况页，SPA 只渲染概况，
    /// 脚本把页头资料卡也当成员收集，导致列表为空/首项是自己。
    private static func pageURL(kind: ListKind, uid: Int, isSelfProfile: Bool) -> URL? {
        var components = URLComponents(url: NodeSeekSite.baseURL, resolvingAgainstBaseURL: false)
        // 关注列表的真实路由是 /fans?type=follow（站点实测 200）；
        // /space/{uid}#/follows 是不存在的路由，SPA 不识别、永远停在概况页。
        components?.path = "/fans"
        components?.queryItems = [
            URLQueryItem(name: "type", value: kind == .fans ? "fans" : "follow")
        ]
        return components?.url
    }

    /// 粉丝/关注列表由登录态 SPA 渲染。先 URLSession 拉 SSR（登录 cookie 已带），
    /// 粉丝/关注列表均为 /fans 独立页纯 SPA 渲染（SSR 无成员卡，日志已证），
    /// 登录态下直接走 WebView 打开真实路由 + 脚本轮询收集。
    private static func fetchEntries(kind: ListKind, uid: Int, isSelfProfile: Bool) async -> [FansListEntry] {
        await fetchEntriesViaWebView(kind: kind, uid: uid, isSelfProfile: isSelfProfile)
    }

    /// WebView 加载真实列表路由（登录态 + Cloudflare 已放行），脚本轮询 SPA 渲染的成员卡。
    private static func fetchEntriesViaWebView(kind: ListKind, uid: Int, isSelfProfile: Bool) async -> [FansListEntry] {
        guard let referer = pageURL(kind: kind, uid: uid, isSelfProfile: isSelfProfile) else { return [] }
        do {
            let object = try await withHiddenWebViewPageActionLoader(
                logMessage: "准备通过隐藏 WebView 抓取\(kind.title)列表: uid=\(uid), url=\(referer.absoluteString)"
            ) { loader in
                try await loader.runPageAutomationScript(
                    pageURL: referer,
                    source: SpaceMemberListAutomationScript.source,
                    arguments: ["timeoutMs": 8_000, "ownerUid": uid],
                    timeoutInterval: 14,
                    actionName: "空间成员列表",
                    requireCleanPage: false
                )
            }
            let entries = (object["entries"] as? [[String: Any]] ?? []).compactMap { raw -> FansListEntry? in
                guard let name = raw["name"] as? String, name.isEmpty == false else { return nil }
                let userID = (raw["uid"] as? NSNumber)?.intValue ?? (raw["uid"] as? Int)
                let avatarHref = raw["avatar"] as? String ?? ""
                let avatarURL = URL(string: avatarHref, relativeTo: NodeSeekSite.baseURL)?.absoluteURL
                return FansListEntry(userID: userID, name: name, avatarURL: avatarURL, metaText: nil)
            }
            AppLog.info(.account, "\(kind.title)列表 WebView 脚本返回: count=\(entries.count), reason=\(object["reason"] as? String ?? "unknown")")
            return entries
        } catch {
            AppLog.warning(.account, "\(kind.title)列表 WebView 抓取失败: \(error.localizedDescription)")
            return []
        }
    }

    private static func parseEntries(html: String, kind: ListKind) -> [FansListEntry] {
        FansListHTMLParser.parse(html: html, kindKeyword: kind == .fans ? "粉丝" : "关注")
    }

    private func applyDisplayState() {
        switch displayMode {
        case .content:
            loadingIndicator.stopAnimating()
            tableView.backgroundView = entries.isEmpty ? emptyView(text: "暂无\(kind.title)") : nil
        case .loading:
            loadingIndicator.startAnimating()
            tableView.backgroundView = loadingIndicator
        case .error:
            loadingIndicator.stopAnimating()
            tableView.backgroundView = errorLabel
        }
    }

    private func emptyView(text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }
}

extension FansListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let entry = entries[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = entry.name
        configuration.secondaryText = entry.metaText
        configuration.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = configuration

        let avatar = UIImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 20
        avatar.image = UIImage(systemName: "person.crop.circle.fill")
        avatar.tintColor = .tertiaryLabel
        if let url = entry.avatarURL {
            ImageLoad.url(url)
                .toAvatar(requestID: "\(entry.userID ?? 0)-fans")
                .into(avatar)
        }
        cell.accessoryView = avatar
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let userID = entries[indexPath.row].userID else { return }
        navigationController?.pushViewController(
            ProfileTabViewController(userID: userID),
            animated: true
        )
    }
}

/// 空间页 HTML 的成员列表容错解析。
enum FansListHTMLParser {
    static func parse(html: String, kindKeyword: String) -> [FansListEntry] {
        guard let document = try? HTML(html: html, encoding: .utf8) else {
            return []
        }
        var entries: [FansListEntry] = []
        let seenIDs = NSMutableSet()

        // 空间页成员卡：优先在 hash 面板渲染容器内找（class 含 fans/follow），
        // 再放宽到 member 容器，最后才全页。
        var anchors = document.xpath("//*[contains(@class,'fans') or contains(@class,'follow')]//a[contains(@href,'/space/')]")
        if anchors.count == 0 {
            anchors = document.xpath("//*[contains(@class,'member')]//a[contains(@href,'/space/')]")
        }
        if anchors.count == 0 {
            anchors = document.xpath("//a[contains(@href,'/space/')]")
        }
        for anchor in anchors {
            let href = anchor["href"] ?? ""
            guard let userID = Self.userID(fromHref: href), userID > 0 else { continue }
            if seenIDs.contains(userID) { continue }
            let card = anchor.parent ?? anchor
            let name = Self.name(fromCard: card, anchor: anchor)
            guard name.isEmpty == false else { continue }
            let avatarHref = Self.avatarHref(fromCard: card)
            seenIDs.add(userID)
            let avatarURL = URL(string: avatarHref, relativeTo: NodeSeekSite.baseURL)?.absoluteURL
            entries.append(FansListEntry(
                userID: userID,
                name: name,
                avatarURL: avatarURL,
                metaText: nil
            ))
        }
        return entries
    }

    private static func name(fromCard card: XMLElement, anchor: XMLElement) -> String {
        if let alt = card.xpath(".//img/@alt").first?.text {
            return alt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let title = card.xpath(".//img/@title").first?.text {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let anchorText = anchor.text ?? ""
        return anchorText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func avatarHref(fromCard card: XMLElement) -> String {
        card.xpath(".//img/@src").first?.text ?? ""
    }

    private static func userID(fromHref href: String) -> Int? {
        let components = href.split(separator: "/")
        guard let spaceIndex = components.firstIndex(of: "space"),
              spaceIndex + 1 < components.count else { return nil }
        return Int(components[spaceIndex + 1])
    }
}
