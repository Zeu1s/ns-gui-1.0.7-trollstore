//
//  LogFileViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import UIKit

final class LogFileViewController: UITableViewController {
    private var files: [AppLogFile] = []

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "监控日志"
        navigationItem.largeTitleDisplayMode = .never
        tableView.accessibilityIdentifier = "log-file-list-table-view"
        navigationItem.rightBarButtonItems = [
            makeBarButton(systemName: "trash", accessibilityLabel: "清空全部监控日志", action: #selector(clearAllButtonTapped), tintColor: .systemRed),
            makeBarButton(systemName: "square.and.arrow.up", accessibilityLabel: "分享全部监控日志", action: #selector(shareAllButtonTapped)),
            makeBarButton(systemName: "arrow.clockwise", accessibilityLabel: "刷新监控日志", action: #selector(refreshButtonTapped))
        ]
        reloadFiles()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadFiles()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "monitoring-log-file-cell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let file = files[indexPath.row]
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = file.displayName
        configuration.secondaryText = file.sizeText
        configuration.image = UIImage(systemName: "doc.text")
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "monitoring-log-file-\(indexPath.row)"
        cell.accessibilityLabel = "\(file.displayName)，\(file.sizeText)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard files.indices.contains(indexPath.row) else { return }
        navigationController?.pushViewController(LogFileContentViewController(file: files[indexPath.row]), animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard files.indices.contains(indexPath.row) else { return nil }
        let file = files[indexPath.row]
        let share = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
            self?.share(file)
            completion(true)
        }
        share.image = UIImage(systemName: "square.and.arrow.up")
        share.backgroundColor = .systemBlue

        let delete = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
            self?.delete(file)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete, share])
    }

    private func makeBarButton(
        systemName: String,
        accessibilityLabel: String,
        action: Selector,
        tintColor: UIColor? = nil
    ) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: systemName),
            style: .plain,
            target: self,
            action: action
        )
        item.accessibilityLabel = accessibilityLabel
        item.tintColor = tintColor
        return item
    }

    @objc private func refreshButtonTapped() {
        reloadFiles()
    }

    @objc private func shareAllButtonTapped() {
        do {
            let urls = try AppLog.exportAllFileLogs()
            presentShareSheet(items: urls.map { $0 as Any })
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func clearAllButtonTapped() {
        let alert = UIAlertController(
            title: "清空全部监控日志？",
            message: "所有时间分段日志会被永久删除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            do {
                try AppLog.deleteAllFileLogs()
                self?.reloadFiles()
            } catch {
                self?.presentError(error.localizedDescription)
            }
        })
        present(alert, animated: true)
    }

    private func share(_ file: AppLogFile) {
        do {
            presentShareSheet(items: [try AppLog.exportFileLog(file)])
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func delete(_ file: AppLogFile) {
        do {
            try AppLog.deleteFileLog(file)
            reloadFiles()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func reloadFiles() {
        do {
            files = try AppLog.logFiles()
        } catch {
            files = []
            presentError(error.localizedDescription)
        }
        tableView.reloadData()
        let label = UILabel()
        label.text = files.isEmpty ? "暂无监控日志" : nil
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        tableView.backgroundView = files.isEmpty ? label : nil
    }

    private func presentShareSheet(items: [Any]) {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(activity, animated: true)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "监控日志", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

private final class LogFileContentViewController: UIViewController {
    private let file: AppLogFile
    private let textView: UITextView = {
        let textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        textView.accessibilityIdentifier = "log-file-content-text-view"
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    init(file: AppLogFile) {
        self.file = file
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = file.displayName
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareButtonTapped)),
            UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(copyButtonTapped)),
            UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(refreshButtonTapped))
        ]
        navigationItem.rightBarButtonItems?[0].accessibilityLabel = "分享这段监控日志"
        navigationItem.rightBarButtonItems?[1].accessibilityLabel = "复制这段监控日志"
        navigationItem.rightBarButtonItems?[2].accessibilityLabel = "刷新这段监控日志"
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        reloadContent()
    }

    @objc private func refreshButtonTapped() {
        reloadContent()
    }

    @objc private func copyButtonTapped() {
        UIPasteboard.general.string = textView.text
    }

    @objc private func shareButtonTapped() {
        do {
            let activity = UIActivityViewController(activityItems: [try AppLog.exportFileLog(file)], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.barButtonItem = navigationItem.rightBarButtonItems?.first
            }
            present(activity, animated: true)
        } catch {
            textView.text = "读取监控日志失败：\(error.localizedDescription)"
        }
    }

    private func reloadContent() {
        do {
            let content = try AppLog.fileLogContent(for: file)
            textView.text = content.isEmpty ? "暂无监控日志" : content
            scrollToBottom()
        } catch {
            textView.text = "读取监控日志失败：\(error.localizedDescription)"
        }
    }

    private func scrollToBottom() {
        let textLength = (textView.text as NSString).length
        guard textLength > 0 else { return }
        let bottomRange = NSRange(location: textLength - 1, length: 1)
        DispatchQueue.main.async { [weak self] in
            self?.textView.scrollRangeToVisible(bottomRange)
        }
    }
}