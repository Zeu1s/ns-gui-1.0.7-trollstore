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

    private let kind: ListKind
    private let uid: Int

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
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

    private init(kind: ListKind, uid: Int) {
        self.kind = kind
        self.uid = uid
        super.init(nibName: nil, bundle: nil)
        title = "\(kind.title)列表"
    }

    convenience init(fansOf uid: Int) {
        self.init(kind: .fans, uid: uid)
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
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func refreshTriggered() {
        reload()
    }

    private func reload() {
        displayMode = entries.isEmpty ? .loading : .content
        applyDisplayState()
        Task { [weak self] in
            guard let self else { return }
            let loaded = await Self.fetchEntries(kind: self.kind, uid: self.uid)
            guard self.isViewLoaded else { return }
            self.entries = loaded
            self.refreshControl.endRefreshing()
            if loaded.isEmpty && self.entries.isEmpty == false {
                self.displayMode = .content
            } else if loaded.isEmpty {
                self.displayMode = .error
                self.errorLabel.text = "暂无\(self.kind.title)或加载失败（网页结构可能已变化）"
            } else {
                self.displayMode = .content
            }
            self.applyDisplayState()
            self.tableView.reloadData()
        }
    }

    /// 空间页粉丝/关注列表由登录态 SPA 渲染（数据 chunk 登录后才加载），
    /// 直接走隐藏 WebView 拿渲染完成的 HTML；HTTP 结果不含成员卡，仅作兜底跳过。
    private static func fetchEntries(kind: ListKind, uid: Int) async -> [FansListEntry] {
        let baseURL = NodeSeekSite.baseURL
        var components = URLComponents(url: baseURL.appendingPathComponent("space"), resolvingAgainstBaseURL: false)
        components?.path = "/space/\(uid)"
        components?.fragment = String(kind.hashRoute.dropFirst())
        guard let url = components?.url else { return [] }

        let client = HTMLLoadingStrategyFactory.makeDefaultClient()
        // 后台补全在跑时先让路 2 秒，降低抢锁超时概率。
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if let fallbackClient = client as? any WebViewFallbackRetrying {
            if let response = try? await fallbackClient.getUsingWebViewFallback(url) {
                let parsed = parseEntries(html: response.html, kind: kind)
                if parsed.isEmpty == false {
                    return parsed
                }
            }
        }
        if let response = try? await client.get(url),
           (200..<300).contains(response.statusCode) {
            return parseEntries(html: response.html, kind: kind)
        }
        return []
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

        // 空间页成员卡：优先在成员列表容器内找（class 含 member/fans/follow/list），
        // 避免把页面导航/介绍区的 space 链接误判为粉丝。
        var anchors = document.xpath("//*[contains(@class,'member') or contains(@class,'fans') or contains(@class,'follow')]//a[contains(@href,'/space/')]")
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
