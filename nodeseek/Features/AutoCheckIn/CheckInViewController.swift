//
//  CheckInViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class CheckInViewController: UIViewController {
    private let automator: AutoCheckInWebAutomating
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let fixedButton = UIButton(type: .system)
    private let randomButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var boardState: AutoCheckInBoardState?
    private var isLoading = false

    init(automator: AutoCheckInWebAutomating? = nil) {
        self.automator = automator ?? HTTPAutoCheckInAutomator()
        super.init(nibName: nil, bundle: nil)
        title = "签到"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureUI()
        loadBoardState()
    }

    private func configureUI() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshTapped)
        )

        statusLabel.font = .preferredFont(forTextStyle: .title2)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true

        configureButton(fixedButton, title: "签到领取鸡腿 x 5", selector: #selector(fixedCheckInTapped))
        configureButton(randomButton, title: "试试手气", selector: #selector(randomCheckInTapped))
        fixedButton.accessibilityIdentifier = "check-in-fixed-button"
        randomButton.accessibilityIdentifier = "check-in-random-button"

        let stack = UIStackView(arrangedSubviews: [statusLabel, detailLabel, fixedButton, randomButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            fixedButton.heightAnchor.constraint(equalToConstant: 48),
            randomButton.heightAnchor.constraint(equalToConstant: 48),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 20)
        ])
        statusLabel.text = "正在读取签到状态..."
        detailLabel.text = ""
        updateActionsEnabled()
    }

    private func configureButton(_ button: UIButton, title: String, selector: Selector) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = .systemOrange
        configuration.baseForegroundColor = .white
        button.configuration = configuration
        button.addTarget(self, action: selector, for: .touchUpInside)
    }

    @objc private func refreshTapped() {
        loadBoardState()
    }

    @objc private func fixedCheckInTapped() {
        submit(mode: .fixedChickenLeg)
    }

    @objc private func randomCheckInTapped() {
        submit(mode: .random)
    }

    private func loadBoardState() {
        guard isLoading == false else { return }
        isLoading = true
        updateActionsEnabled()
        activityIndicator.startAnimating()
        Task { [weak self] in
            guard let self else { return }
            do {
                boardState = try await automator.fetchBoardState(runID: "manual")
                updateStatus()
            } catch {
                boardState = nil
                statusLabel.text = "无法读取签到状态"
                detailLabel.text = error.localizedDescription
            }
            isLoading = false
            activityIndicator.stopAnimating()
            updateActionsEnabled()
        }
    }

    private func submit(mode: AutoCheckInMode) {
        guard isLoading == false else { return }
        guard boardState?.isCheckedIn != true else { return }
        guard boardState?.isLoggedIn != false else {
            presentLoginRequired()
            return
        }
        isLoading = true
        updateActionsEnabled()
        activityIndicator.startAnimating()
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await automator.submit(mode: mode, runID: "manual")
                if result.ok {
                    statusLabel.text = "今日已签到"
                    detailLabel.text = result.message ?? "签到成功。"
                    boardState = AutoCheckInBoardState(
                        ok: true,
                        isLoggedIn: true,
                        isCheckedIn: true,
                        message: result.message,
                        detectionSource: "manual_submit",
                        reason: "submitted",
                        statusCode: result.statusCode,
                        responseKeys: []
                    )
                } else if isLoginMessage(result.message) {
                    presentLoginRequired()
                } else {
                    presentError(result.message ?? "签到未完成，请稍后重试。")
                }
            } catch {
                presentError(error.localizedDescription)
            }
            isLoading = false
            activityIndicator.stopAnimating()
            updateActionsEnabled()
        }
    }

    private func updateStatus() {
        guard let boardState else { return }
        if boardState.isCheckedIn {
            statusLabel.text = "今日已签到"
            detailLabel.text = boardState.message ?? "明天再来。"
        } else if boardState.isLoggedIn {
            statusLabel.text = "今日尚未签到"
            detailLabel.text = boardState.message ?? "选择一种签到方式。"
        } else {
            statusLabel.text = "需要登录"
            detailLabel.text = "登录后即可完成签到。"
        }
    }

    private func updateActionsEnabled() {
        let canSubmit = isLoading == false && boardState?.isCheckedIn != true && boardState?.isLoggedIn != false
        fixedButton.isEnabled = canSubmit
        randomButton.isEnabled = canSubmit
        navigationItem.rightBarButtonItem?.isEnabled = !isLoading
    }

    private func presentLoginRequired() {
        let alert = UIAlertController(title: "需要登录", message: "签到需要先完成 NodeSeek 登录。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "去登录", style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(LoginWebViewController(), animated: true)
        })
        present(alert, animated: true)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "签到失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func isLoginMessage(_ message: String?) -> Bool {
        let normalized = message?.lowercased() ?? ""
        return normalized.contains("user not found") || normalized.contains("not login") || normalized.contains("未登录")
    }
}
