//
//  NodeSeekSystemSettingsViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class NodeSeekSystemSettingsViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case personalInfo
        case security
        case twoFactor
        case contact
        case blockedUsers
        case preferences
        case homepage
        case extensions

        var title: String {
            switch self {
            case .personalInfo: return "个人信息"
            case .security: return "安全"
            case .twoFactor: return "双因素验证"
            case .contact: return "联系方式"
            case .blockedUsers: return "屏蔽用户"
            case .preferences: return "常用偏好"
            case .homepage: return "首页版块"
            case .extensions: return "论坛扩展"
            }
        }

        var imageName: String {
            switch self {
            case .personalInfo: return "person.text.rectangle"
            case .security: return "lock"
            case .twoFactor: return "key.viewfinder"
            case .contact: return "person.crop.circle.badge.checkmark"
            case .blockedUsers: return "person.crop.circle.badge.xmark"
            case .preferences: return "slider.horizontal.3"
            case .homepage: return "rectangle.grid.2x2"
            case .extensions: return "puzzlepiece.extension"
            }
        }

        var route: String? {
            switch self {
            case .personalInfo: return nil
            case .security: return "security"
            case .twoFactor: return "2fa"
            case .contact: return "contact"
            case .blockedUsers: return "block"
            case .preferences: return "preference"
            case .homepage: return "homepage"
            case .extensions: return "extend"
            }
        }
    }

    private let currentAccountStore: CurrentAccountStore

    init(currentAccountStore: CurrentAccountStore = .shared) {
        self.currentAccountStore = currentAccountStore
        super.init(style: .insetGrouped)
        title = "NodeSeek 设置"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 54
        tableView.accessibilityIdentifier = "nodeseek-system-settings-table-view"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard let row = Row(rawValue: indexPath.row) else { return cell }
        var configuration = cell.defaultContentConfiguration()
        configuration.text = row.title
        configuration.image = UIImage(systemName: row.imageName)
        configuration.imageProperties.tintColor = .systemOrange
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "nodeseek-system-settings-\(row.rawValue)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Row(rawValue: indexPath.row) else { return }
        switch row {
        case .personalInfo:
            navigationController?.pushViewController(
                NodeSeekAccountProfileViewController(currentAccountStore: currentAccountStore),
                animated: true
            )
        case .security, .twoFactor, .contact, .blockedUsers, .preferences, .homepage, .extensions:
            guard let route = row.route,
                  let url = URL(string: "https://www.nodeseek.com/setting#\(route)") else {
                return
            }
            navigationController?.pushViewController(
                NodeSeekWebViewController(
                    url: url,
                    pageTitle: row.title,
                    allowsPageZoom: true,
                    additionalUserScripts: WebViewStyleInjectionScriptFactory.makeStyleInjectionScripts(
                        css: Self.systemSettingsPageCSS
                    )
                ),
                animated: true
            )
        }
    }

    private static let systemSettingsPageCSS = """
    html,
    body {
      width: 100% !important;
      max-width: 100% !important;
      overflow-x: hidden !important;
    }
    #nsk-head,
    #nsk-left-panel-container,
    #nsk-right-panel-container,
    #nsk-body-right {
      display: none !important;
    }
    #nsk-frame,
    #nsk-body,
    #nsk-body-left {
      display: block !important;
      width: 100% !important;
      max-width: 100% !important;
      min-width: 0 !important;
      margin-left: 0 !important;
      margin-right: 0 !important;
      box-sizing: border-box !important;
    }
    #nsk-body {
      padding: 0 !important;
    }
    #nsk-body-left {
      padding: 12px 16px 24px !important;
    }
    #nsk-body-left *,
    #nsk-body-left img,
    #nsk-body-left input,
    #nsk-body-left select,
    #nsk-body-left textarea,
    #nsk-body-left button {
      max-width: 100% !important;
      box-sizing: border-box !important;
    }
    """
}
