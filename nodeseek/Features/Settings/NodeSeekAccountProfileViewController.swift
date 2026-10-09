//
//  NodeSeekAccountProfileViewController.swift
//  nodeseek
//

import PhotosUI
import UIKit

@MainActor
final class NodeSeekAccountProfileViewController: UIViewController {
    private let client: NodeSeekAccountSettingsManaging
    private let currentAccountStore: CurrentAccountStore

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let avatarImageView = UIImageView()
    private let avatarButton = UIButton(type: .system)
    private let bioTextField = UITextField()
    private let signatureTextView = UITextView()
    private let readmeTextView = UITextView()
    private let statusLabel = UILabel()

    private var account: AccountResponse?
    private var userID: Int?
    private var isSaving = false
    private var isUploadingAvatar = false

    init(
        client: NodeSeekAccountSettingsManaging? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
        self.client = client ?? NodeSeekAccountSettingsClient()
        self.currentAccountStore = currentAccountStore
        super.init(nibName: nil, bundle: nil)
        title = "个人信息"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureNavigation()
        configureUI()
        setEditable(false)
        loadProfile()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "保存个人信息"
    }

    private func configureUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 28, right: 20)

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.backgroundColor = .secondarySystemBackground
        avatarImageView.layer.cornerRadius = 44
        avatarImageView.clipsToBounds = true
        avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarImageView.tintColor = .tertiaryLabel

        var avatarConfiguration = UIButton.Configuration.tinted()
        avatarConfiguration.title = "更换头像"
        avatarConfiguration.image = UIImage(systemName: "photo")
        avatarConfiguration.imagePadding = 6
        avatarButton.configuration = avatarConfiguration
        avatarButton.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)
        avatarButton.accessibilityLabel = "更换头像"

        let avatarRow = UIStackView(arrangedSubviews: [avatarImageView, avatarButton])
        avatarRow.axis = .horizontal
        avatarRow.alignment = .center
        avatarRow.spacing = 18
        avatarRow.translatesAutoresizingMaskIntoConstraints = false
        avatarRow.heightAnchor.constraint(equalToConstant: 88).isActive = true
        avatarImageView.widthAnchor.constraint(equalToConstant: 88).isActive = true
        avatarImageView.heightAnchor.constraint(equalToConstant: 88).isActive = true

        configureTextField(bioTextField, placeholder: "用一句话介绍自己")
        configureTextView(signatureTextView, placeholder: "支持 Markdown，不支持图片和引用")
        configureTextView(readmeTextView, placeholder: "显示在用户主页，支持 Markdown")
        signatureTextView.heightAnchor.constraint(equalToConstant: 160).isActive = true
        readmeTextView.heightAnchor.constraint(equalToConstant: 210).isActive = true

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.isHidden = true

        contentStack.addArrangedSubview(section(title: "头像", content: avatarRow))
        contentStack.addArrangedSubview(section(title: "Bio", content: bioTextField))
        contentStack.addArrangedSubview(section(title: "签名", content: signatureTextView))
        contentStack.addArrangedSubview(section(title: "Readme", content: readmeTextView))
        contentStack.addArrangedSubview(statusLabel)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func configureTextField(_ textField: UITextField, placeholder: String) {
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.placeholder = placeholder
        textField.backgroundColor = .secondarySystemBackground
        textField.layer.cornerRadius = 8
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.setLeftPadding(12)
        textField.setRightPadding(12)
        textField.heightAnchor.constraint(equalToConstant: 46).isActive = true
    }

    private func configureTextView(_ textView: UITextView, placeholder: String) {
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.accessibilityHint = placeholder
    }

    private func section(title: String, content: UIView) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.text = title
        titleLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, content])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func loadProfile() {
        setStatus("正在加载个人信息…")
        Task { [weak self] in
            guard let self else { return }
            guard let snapshot = await currentAccountStore.snapshot(),
                  snapshot.account.isLoggedIn,
                  let userID = snapshot.account.nodeSeekUID else {
                setStatus("登录后才能编辑个人信息。")
                setEditable(false)
                return
            }

            account = snapshot.account
            self.userID = userID
            setEditable(true)
            updateActions()
            loadAvatar(for: userID, fallback: snapshot.account.avatarURL)
            do {
                let profile = try await client.loadProfile(userID: userID)
                bioTextField.text = profile.bio
                signatureTextView.text = profile.signature
                readmeTextView.text = profile.readme
                setStatus(nil)
            } catch {
                setStatus(error.localizedDescription)
            }
        }
    }

    private func loadAvatar(for userID: Int, fallback: URL?) {
        let url = fallback ?? NodeSeekNotificationURLBuilder.avatarURL(memberID: userID)
        ImageLoad.url(url)
            .toAvatar(requestID: "account-settings-\(userID)")
            .into(avatarImageView)
    }

    @objc private func saveTapped() {
        guard userID != nil, isSaving == false, isUploadingAvatar == false else { return }
        guard let profile = validatedProfile() else { return }
        isSaving = true
        updateActions()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.updateProfile(profile)
                isSaving = false
                updateActions()
                setStatus("已保存")
            } catch {
                isSaving = false
                updateActions()
                presentError(error.localizedDescription)
            }
        }
    }

    @objc private func avatarTapped() {
        guard userID != nil, isSaving == false, isUploadingAvatar == false else { return }
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func validatedProfile() -> NodeSeekAccountEditableProfile? {
        let signature = signatureTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if signature.localizedCaseInsensitiveContains("<img") || signature.contains("![") {
            presentError("签名不支持图片。")
            return nil
        }
        if signature.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }) {
            presentError("签名不支持引用。")
            return nil
        }
        return NodeSeekAccountEditableProfile(
            bio: bioTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            signature: signature,
            readme: readmeTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func uploadAvatar(_ image: UIImage) {
        guard let avatar = Self.avatarPNG(from: image) else {
            presentError("无法处理所选图片。")
            return
        }
        isUploadingAvatar = true
        updateActions()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.uploadAvatarPNG(avatar.data)
                guard Task.isCancelled == false else { return }
                avatarImageView.image = avatar.image
                await refreshStoredAvatarURL()
                isUploadingAvatar = false
                updateActions()
                setStatus("头像已更新")
            } catch {
                guard Task.isCancelled == false else { return }
                isUploadingAvatar = false
                updateActions()
                presentError(error.localizedDescription)
            }
        }
    }

    private func refreshStoredAvatarURL() async {
        guard let account, let userID else { return }
        var components = URLComponents(url: NodeSeekNotificationURLBuilder.avatarURL(memberID: userID), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "updated", value: "\(Int(Date().timeIntervalSince1970))")]
        let avatarURL = components?.url ?? NodeSeekNotificationURLBuilder.avatarURL(memberID: userID)
        let refreshedAccount = AccountResponse(
            displayName: account.displayName,
            isLoggedIn: account.isLoggedIn,
            avatarURL: avatarURL,
            profileURL: account.profileURL,
            stats: account.stats,
            notification: account.notification
        )
        self.account = refreshedAccount
        await currentAccountStore.save(refreshedAccount)
    }

    private func setStatus(_ message: String?) {
        statusLabel.text = message
        statusLabel.isHidden = message == nil
    }

    private func setEditable(_ editable: Bool) {
        bioTextField.isEnabled = editable
        signatureTextView.isEditable = editable
        readmeTextView.isEditable = editable
        avatarButton.isEnabled = editable
        navigationItem.rightBarButtonItem?.isEnabled = editable
    }

    private func updateActions() {
        let enabled = isSaving == false && isUploadingAvatar == false && userID != nil
        avatarButton.isEnabled = enabled
        navigationItem.rightBarButtonItem?.isEnabled = enabled
        navigationItem.rightBarButtonItem?.customView?.isUserInteractionEnabled = enabled
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "操作失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private static func avatarPNG(from image: UIImage) -> (image: UIImage, data: Data)? {
        let targetSize = CGSize(width: 100, height: 100)
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let avatar = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        guard let data = avatar.pngData() else { return nil }
        return (avatar, data)
    }
}

extension NodeSeekAccountProfileViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image = image as? UIImage else {
                    self.presentError(error?.localizedDescription ?? "无法读取所选图片。")
                    return
                }
                self.uploadAvatar(image)
            }
        }
    }
}

private extension UITextField {
    func setLeftPadding(_ value: CGFloat) {
        leftView = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftViewMode = .always
    }

    func setRightPadding(_ value: CGFloat) {
        rightView = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        rightViewMode = .always
    }
}
