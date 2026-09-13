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

    /// 空间页粉丝/关注列表由登录态 SPA 渲染。SPA 从 hash 启动后异步拉取
    /// 成员数据，概况页即可满足 usableContent 判定导致提前返回，因此改用
    /// 页面内脚本轮询：等成员卡（/space/ 链接）出现或超时，再收集结果。
    /// 粉丝/关注：URLSession.shared 拉空间页（登录 cookie 已带）。
    /// 站点空间页 SSR 若内嵌成员卡则解析；否则返回空（由上层提示用浏览器打开）。
    private static func fetchEntries(kind: ListKind, uid: Int) async -> [FansListEntry] {
        var components = URLComponents(url: NodeSeekSite.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/space/\(uid)"
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        WebRequestFingerprint.applyHTMLHeaders(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            let parsed = parseEntries(html: html, kind: kind)
            if parsed.isEmpty == false {
                return parsed
            }
            return []
        } catch {
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
