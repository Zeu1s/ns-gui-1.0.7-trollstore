//
//  MonitoringLogSettingsViewController.swift
//  nodeseek
//

import UIKit

final class MonitoringLogSettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case recording
        case logs
    }

    private enum RecordingRow: Int, CaseIterable {
        case enabled
    }

    private enum LogRow: Int, CaseIterable {
        case view
        case export
        case clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "监控日志"
        tableView.accessibilityIdentifier = "monitoring-log-settings-table-view"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .recording:
            return RecordingRow.allCases.count
        case .logs:
            return LogRow.allCases.count
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .recording:
            return "记录"
        case .logs:
            return "日志"
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch section {
        case .recording:
            return recordingCell()
        case .logs:
            return logCell(for: LogRow(rawValue: indexPath.row))
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .logs,
              let row = LogRow(rawValue: indexPath.row) else {
            return
        }
        switch row {
        case .view:
            navigationController?.pushViewController(LogFileViewController(), animated: true)
        case .export:
            exportLog()
        case .clear:
            confirmClearLog()
        }
    }

    private func recordingCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = "记录全程监控"
        cell.detailTextLabel?.text = "记录动作、加载、卡顿与异常退出"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: "waveform.path.ecg")
        let toggle = UISwitch()
        toggle.isOn = NodeSeekDebugConfig.enableFileLogging
        toggle.accessibilityIdentifier = "monitoring-log-enabled-switch"
        toggle.addTarget(self, action: #selector(recordingSwitchChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "monitoring-log-enabled-cell"
        return cell
    }

    private func logCell(for row: LogRow?) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        switch row {
        case .view:
            cell.textLabel?.text = "日志列表"
            cell.imageView?.image = UIImage(systemName: "doc.text")
            cell.accessibilityIdentifier = "monitoring-log-view-cell"
        case .export:
            cell.textLabel?.text = "导出全部日志"
            cell.imageView?.image = UIImage(systemName: "square.and.arrow.up")
            cell.accessibilityIdentifier = "monitoring-log-export-cell"
        case .clear:
            cell.textLabel?.text = "清空全部日志"
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.image = UIImage(systemName: "trash")
            cell.imageView?.tintColor = .systemRed
            cell.accessibilityIdentifier = "monitoring-log-clear-cell"
        case .none:
            return cell
        }
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    @objc private func recordingSwitchChanged(_ sender: UISwitch) {
        if sender.isOn {
            NodeSeekDebugConfig.enableFileLogging = true
            AppRuntimeMonitor.shared.monitoringSettingDidChange(isEnabled: true)
            AppLog.notice(.runtime, "用户已开启全程监控")
        } else {
            AppRuntimeMonitor.shared.monitoringSettingDidChange(isEnabled: false)
            NodeSeekDebugConfig.enableFileLogging = false
        }
        tableView.reloadSections(IndexSet(integer: Section.recording.rawValue), with: .none)
    }

    private func exportLog() {
        do {
            let urls = try AppLog.exportAllFileLogs()
            let activity = UIActivityViewController(activityItems: urls.map { $0 as Any }, applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top, width: 1, height: 1)
            }
            present(activity, animated: true)
        } catch {
            presentMessage(title: "暂无监控日志", message: error.localizedDescription)
        }
    }

    private func confirmClearLog() {
        let alert = UIAlertController(
            title: "清除监控日志？",
            message: "所有时间分段日志会被永久删除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.clearLog()
        })
        present(alert, animated: true)
    }

    private func clearLog() {
        do {
            try AppLog.deleteAllFileLogs()
            presentMessage(title: "已清空监控日志", message: "之后记录的新事件会按 10 分钟自动分段保存。")
        } catch {
            presentMessage(title: "清除失败", message: error.localizedDescription)
        }
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}