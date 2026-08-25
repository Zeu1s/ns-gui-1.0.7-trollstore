//
//  StardustTransferViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class StardustTransferViewController: UIViewController {
    private let recipientID: Int
    private let recipientName: String
    private let client: NodeSeekUserRelationshipManaging
    private let amountField = UITextField()
    private let referenceField = UITextField()
    private let sendButton = UIButton(type: .system)
    private var isSending = false

    init(
        recipientID: Int,
        recipientName: String,
        client: NodeSeekUserRelationshipManaging = NodeSeekUserRelationshipClient()
    ) {
        self.recipientID = recipientID
        self.recipientName = recipientName
        self.client = client
        super.init(nibName: nil, bundle: nil)
        title = "星辰转账"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureForm()
    }

    private func configureForm() {
        let recipientLabel = UILabel()
        recipientLabel.font = .preferredFont(forTextStyle: .headline)
        recipientLabel.textColor = .label
        recipientLabel.numberOfLines = 0
        recipientLabel.text = "收款人  \(recipientName)"

        let idLabel = UILabel()
        idLabel.font = .preferredFont(forTextStyle: .footnote)
        idLabel.textColor = .secondaryLabel
        idLabel.text = "UID \(recipientID)"

        amountField.placeholder = "星辰数量"
        amountField.keyboardType = .numberPad
        amountField.borderStyle = .roundedRect
        amountField.accessibilityLabel = "星辰数量"

        referenceField.placeholder = "引用编号（可留空）"
        referenceField.keyboardType = .numberPad
        referenceField.borderStyle = .roundedRect
        referenceField.text = "0"
        referenceField.accessibilityLabel = "引用编号"

        var configuration = UIButton.Configuration.filled()
        configuration.title = "继续"
        configuration.image = UIImage(systemName: "arrow.right.circle.fill")
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = .systemBlue
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18)
        sendButton.configuration = configuration
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.accessibilityLabel = "确认星辰转账"

        let noteLabel = UILabel()
        noteLabel.font = .preferredFont(forTextStyle: .footnote)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0
        noteLabel.text = "提交前会再次核对收款人。确认后将调用 NodeSeek 官方星辰转账接口。"

        let stack = UIStackView(arrangedSubviews: [recipientLabel, idLabel, amountField, referenceField, sendButton, noteLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28)
        ])
        amountField.heightAnchor.constraint(equalToConstant: 46).isActive = true
        referenceField.heightAnchor.constraint(equalToConstant: 46).isActive = true
        sendButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }

    @objc private func sendTapped() {
        guard !isSending else { return }
        guard let amountText = amountField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let amount = Int(amountText), amount > 0 else {
            presentMessage(title: "请输入数量", message: "星辰数量必须是大于 0 的整数。")
            return
        }
        let referenceID = Int(referenceField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        isSending = true
        sendButton.configuration?.showsActivityIndicator = true
        sendButton.isEnabled = false

        Task { [weak self] in
            guard let self else { return }
            do {
                let recipient = try await client.prepareStardustTransfer(to: recipientID)
                isSending = false
                sendButton.configuration?.showsActivityIndicator = false
                sendButton.isEnabled = true
                presentTransferConfirmation(recipient: recipient, amount: amount, referenceID: referenceID)
            } catch {
                isSending = false
                sendButton.configuration?.showsActivityIndicator = false
                sendButton.isEnabled = true
                presentMessage(title: "无法准备转账", message: error.localizedDescription)
            }
        }
    }

    private func presentTransferConfirmation(
        recipient: NodeSeekTransferRecipient,
        amount: Int,
        referenceID: Int
    ) {
        let displayName = recipient.username?.isEmpty == false ? recipient.username! : recipientName
        let alert = UIAlertController(
            title: "确认转账",
            message: "向 \(displayName)（UID \(recipientID)）转账 \(amount) 星辰？提交后无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认转账", style: .destructive) { [weak self] _ in
            self?.sendConfirmedTransfer(amount: amount, referenceID: referenceID)
        })
        present(alert, animated: true)
    }

    private func sendConfirmedTransfer(amount: Int, referenceID: Int) {
        guard !isSending else { return }
        isSending = true
        sendButton.configuration?.showsActivityIndicator = true
        sendButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.sendStardustTransfer(to: recipientID, amount: amount, referenceID: referenceID)
                isSending = false
                sendButton.configuration?.showsActivityIndicator = false
                sendButton.isEnabled = true
                let alert = UIAlertController(title: "转账已提交", message: "已向 \(recipientName) 转账 \(amount) 星辰。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "完成", style: .default) { [weak self] _ in
                    self?.navigationController?.popViewController(animated: true)
                })
                present(alert, animated: true)
            } catch {
                isSending = false
                sendButton.configuration?.showsActivityIndicator = false
                sendButton.isEnabled = true
                presentMessage(title: "转账失败", message: error.localizedDescription)
            }
        }
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}
