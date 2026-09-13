//
//  CreditLedgerViewController.swift
//  nodeseek
//

import UIKit

/// 星辰/鸡腿账簿的原生列表页：时间、来源、数量增减、余额。
/// 替代此前网页套壳（移动端排版受限显示不全）。
final class CreditLedgerViewController: UIViewController {
    private enum DisplayMode {
        case content
        case loading
        case error
    }

    private let kind: CreditLedgerRecord.Kind
    private let uid: Int
    private let client = NodeSeekCreditLedgerClient()
    private let records: [CreditLedgerRecord] = []

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refreshControl = UIRefreshControl()
    private let errorLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var items: [CreditLedgerRecord] = []
    private var displayMode: DisplayMode = .loading
    private var currentPage = 1
    private var hasMorePages = true
    private var isLoadingMore = false

    init(kind: CreditLedgerRecord.Kind, uid: Int) {
        self.kind = kind
        self.uid = uid
        super.init(nibName: nil, bundle: nil)
        title = kind == .coin ? "鸡腿明细" : "星辰明细"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureTableView()
        reloadFirstPage()
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
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
        reloadFirstPage()
    }

    private func reloadFirstPage() {
        currentPage = 1
        hasMorePages = true
        load(page: 1, isRefresh: true)
    }

    private func load(page: Int, isRefresh: Bool) {
        if isRefresh {
            displayMode = items.isEmpty ? .loading : .content
            applyDisplayState()
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await client.loadLedger(kind: kind, page: page, uid: uid)
                guard isViewLoaded else { return }
                if page == 1 {
                    items = loaded
                } else {
                    items.append(contentsOf: loaded)
                }
                // 分页终止以接口/站点语义为准（星辰接口返回 total/空页判断），
                // 而非固定每页条数——避免站点改每页大小后提前停止加载。
                hasMorePages = loaded.isEmpty == false
                isLoadingMore = false
                displayMode = .content
                refreshControl.endRefreshing()
                applyDisplayState()
                tableView.reloadData()
            } catch {
                guard isViewLoaded else { return }
                isLoadingMore = false
                refreshControl.endRefreshing()
                if page > 1 {
                    // 追加页失败不清空已显示内容，仅提示。
                    showToast(message: "加载更多失败：\(error.localizedDescription)")
                } else if items.isEmpty {
                    displayMode = .error
                    errorLabel.text = "加载失败：\(error.localizedDescription)"
                    applyDisplayState()
                }
            }
        }
    }

    private func showToast(message: String) {
        let label = UILabel()
        label.text = message
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
        UIView.animate(withDuration: 0.25, animations: { label.alpha = 1 }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                UIView.animate(withDuration: 0.3, animations: { label.alpha = 0 }) { _ in
                    label.removeFromSuperview()
                }
            }
        }
    }

    private func applyDisplayState() {
        switch displayMode {
        case .content:
            loadingIndicator.stopAnimating()
            tableView.backgroundView = items.isEmpty ? emptyView(text: "暂无记录") : nil
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

extension CreditLedgerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        let record = items[indexPath.row]

        configuration.text = record.title
        var secondary: [String] = []
        if let detail = record.detail, detail.isEmpty == false {
            secondary.append(detail)
        }
        if let date = record.date {
            secondary.append(Self.dateText(from: date))
        }
        if let balance = record.balanceAfter {
            secondary.append("余额 \(balance)")
        }
        configuration.secondaryText = secondary.isEmpty ? nil : secondary.joined(separator: " · ")
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)

        let amountLabel = record.amountText
        configuration.textProperties.numberOfLines = 2

        cell.contentConfiguration = configuration

        // 数量徽标：右侧增减色
        let badge = UILabel()
        badge.text = amountLabel
        badge.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        badge.textColor = record.amount == 0
            ? .tertiaryLabel
            : (record.isIncome ? .systemGreen : .systemOrange)
        badge.sizeToFit()
        cell.accessoryView = badge
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard hasMorePages, isLoadingMore == false,
              indexPath.row >= items.count - 5 else { return }
        isLoadingMore = true
        currentPage += 1
        load(page: currentPage, isRefresh: false)
    }

    private static func dateText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
