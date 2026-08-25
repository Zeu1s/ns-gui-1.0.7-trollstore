//
//  PrivateMessageViewController.swift
//  nodeseek
//

import PhotosUI
import SafariServices
import UIKit
import UniformTypeIdentifiers

@MainActor
final class PrivateMessageViewController: UIViewController {
    private let participantID: Int
    private var participantName: String
    private let client: NodeSeekPrivateMessageLoading
    private let currentAccountStore: CurrentAccountStore
    private let nodeImageAPIKeyStore: NodeImageAPIKeyStoring
    private let nodeImageUploadClient: NodeImageUploading

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let emptyLabel = UILabel()
    private let inputBar = UIView()
    private let messageTextView = FormattingTextView()
    private let markdownLabel = UILabel()
    private let markdownSwitch = UISwitch()
    private let imageButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)

    private var messages: [NodeSeekPrivateMessage] = []
    private var currentUserID: Int?
    private var currentUserAvatarURL: URL?
    private var isLoading = false
    private var isSending = false
    private var editingMessageID: Int?
    private var loadingTask: Task<Void, Never>?
    private var imageUploadTask: Task<Void, Never>?

    init(
        participantID: Int,
        participantName: String,
        client: NodeSeekPrivateMessageLoading? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        nodeImageAPIKeyStore: NodeImageAPIKeyStoring = KeychainNodeImageAPIKeyStore(),
        nodeImageUploadClient: NodeImageUploading = NodeImageUploadClient()
    ) {
        self.participantID = participantID
        self.participantName = participantName
        self.client = client ?? NodeSeekPrivateMessageClient()
        self.currentAccountStore = currentAccountStore
        self.nodeImageAPIKeyStore = nodeImageAPIKeyStore
        self.nodeImageUploadClient = nodeImageUploadClient
        super.init(nibName: nil, bundle: nil)
        title = participantName
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadingTask?.cancel()
        imageUploadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureTableView()
        configureComposer()
        loadCurrentAccount()
        loadConversation(scrollToLatest: true)
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 92
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PrivateMessageCell.self, forCellReuseIdentifier: PrivateMessageCell.reuseIdentifier)

        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl

        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.adjustsFontForContentSizeCategory = true

        view.addSubview(tableView)
        view.addSubview(inputBar)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            inputBar.heightAnchor.constraint(equalToConstant: 58)
        ])
    }

    private func configureComposer() {
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.backgroundColor = .secondarySystemBackground
        inputBar.layer.borderWidth = 1 / UIScreen.main.scale
        inputBar.layer.borderColor = UIColor.separator.cgColor

        messageTextView.translatesAutoresizingMaskIntoConstraints = false
        messageTextView.backgroundColor = .systemBackground
        messageTextView.font = .preferredFont(forTextStyle: .body)
        messageTextView.textColor = .label
        messageTextView.layer.cornerRadius = 9
        messageTextView.layer.borderWidth = 1 / UIScreen.main.scale
        messageTextView.layer.borderColor = UIColor.separator.cgColor
        messageTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        messageTextView.returnKeyType = .default
        messageTextView.delegate = self
        messageTextView.accessibilityLabel = "私信内容"
        messageTextView.onPasteImage = { [weak self] image in
            self?.uploadPastedImage(image) ?? false
        }

        markdownLabel.translatesAutoresizingMaskIntoConstraints = false
        markdownLabel.text = "Markdown"
        markdownLabel.font = .preferredFont(forTextStyle: .caption1)
        markdownLabel.textColor = .secondaryLabel
        markdownLabel.adjustsFontForContentSizeCategory = true

        markdownSwitch.translatesAutoresizingMaskIntoConstraints = false
        markdownSwitch.accessibilityLabel = "以 Markdown 发送"
        // 图床返回 Markdown 图片文本，新私信默认按 Markdown 发送以确保图片正常渲染。
        markdownSwitch.isOn = true

        var imageConfiguration = UIButton.Configuration.plain()
        imageConfiguration.image = UIImage(systemName: "camera.fill")
        imageConfiguration.baseForegroundColor = .label
        imageConfiguration.contentInsets = .zero
        imageButton.configuration = imageConfiguration
        imageButton.translatesAutoresizingMaskIntoConstraints = false
        imageButton.accessibilityLabel = "选择图片"
        imageButton.addTarget(self, action: #selector(imageButtonTapped), for: .touchUpInside)

        var sendConfiguration = UIButton.Configuration.plain()
        sendConfiguration.image = UIImage(systemName: "arrow.up.circle.fill")
        sendConfiguration.baseForegroundColor = .systemOrange
        sendConfiguration.contentInsets = .zero
        sendButton.configuration = sendConfiguration
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.accessibilityLabel = "发送"
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        inputBar.addSubview(markdownLabel)
        inputBar.addSubview(markdownSwitch)
        inputBar.addSubview(imageButton)
        inputBar.addSubview(sendButton)
        inputBar.addSubview(messageTextView)
        NSLayoutConstraint.activate([
            markdownLabel.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            markdownLabel.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),

            markdownSwitch.leadingAnchor.constraint(equalTo: markdownLabel.trailingAnchor, constant: 5),
            markdownSwitch.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),

            imageButton.leadingAnchor.constraint(equalTo: markdownSwitch.trailingAnchor, constant: 7),
            imageButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            imageButton.widthAnchor.constraint(equalToConstant: 36),
            imageButton.heightAnchor.constraint(equalToConstant: 44),

            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 44),

            messageTextView.leadingAnchor.constraint(equalTo: imageButton.trailingAnchor, constant: 4),
            messageTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -4),
            messageTextView.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            messageTextView.heightAnchor.constraint(equalToConstant: 40)
        ])
        updateComposerState()
    }

    private func loadCurrentAccount() {
        Task { [weak self] in
            guard let self else { return }
            let account = await currentAccountStore.snapshot()?.account
            currentUserID = account?.nodeSeekUID
            currentUserAvatarURL = account?.avatarURL
            tableView.reloadData()
        }
    }

    private func loadConversation(scrollToLatest: Bool) {
        guard isLoading == false else { return }
        isLoading = true
        emptyLabel.text = messages.isEmpty ? "正在加载私信…" : nil
        updateBackgroundView()

        loadingTask?.cancel()
        loadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let conversation = try await client.loadConversation(with: participantID)
                guard Task.isCancelled == false else { return }
                participantName = conversation.participantName ?? participantName
                title = participantName
                messages = conversation.messages
                isLoading = false
                refreshControl.endRefreshing()
                emptyLabel.text = messages.isEmpty ? "暂无聊天记录，发送第一条私信吧" : nil
                updateBackgroundView()
                tableView.reloadData()
                if scrollToLatest {
                    scrollToLatestMessage()
                }
            } catch {
                guard Task.isCancelled == false else { return }
                isLoading = false
                refreshControl.endRefreshing()
                emptyLabel.text = messages.isEmpty ? error.localizedDescription : nil
                updateBackgroundView()
            }
        }
    }

    private func updateBackgroundView() {
        tableView.backgroundView = messages.isEmpty ? emptyLabel : nil
    }

    private func scrollToLatestMessage() {
        guard messages.isEmpty == false else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, messages.isEmpty == false else { return }
            let indexPath = IndexPath(row: messages.count - 1, section: 0)
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        }
    }

    private func sendCurrentMessage() {
        let content = messageTextView.formattedSubmissionText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false, isSending == false else { return }

        isSending = true
        updateComposerState()
        Task { [weak self] in
            guard let self else { return }
            do {
                if let editingMessageID {
                    try await client.editMessage(
                        id: editingMessageID,
                        content: content,
                        markdown: markdownSwitch.isOn
                    )
                    self.editingMessageID = nil
                } else {
                    try await client.sendMessage(to: participantID, content: content, markdown: markdownSwitch.isOn)
                }
                guard Task.isCancelled == false else { return }
                messageTextView.text = nil
                isSending = false
                updateComposerState()
                loadConversation(scrollToLatest: true)
            } catch {
                guard Task.isCancelled == false else { return }
                isSending = false
                updateComposerState()
                presentError(error.localizedDescription)
            }
        }
    }

    private func updateComposerState() {
        let isUploading = imageUploadTask != nil
        let hasDraft = messageTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let isEditing = editingMessageID != nil
        messageTextView.isEditable = !isSending
        sendButton.isEnabled = hasDraft && !isSending && !isUploading
        imageButton.isEnabled = !isSending && !isUploading
        var sendConfiguration = sendButton.configuration ?? UIButton.Configuration.plain()
        sendConfiguration.image = UIImage(systemName: isEditing ? "checkmark.circle.fill" : "arrow.up.circle.fill")
        sendButton.configuration = sendConfiguration
        sendButton.accessibilityLabel = isEditing ? "保存修改" : "发送"
        sendButton.configuration?.showsActivityIndicator = isSending
        imageButton.configuration?.showsActivityIndicator = isUploading
    }

    @objc private func refreshTriggered() {
        loadConversation(scrollToLatest: false)
    }

    @objc private func sendTapped() {
        sendCurrentMessage()
    }

    @objc private func imageButtonTapped() {
        guard nodeImageAPIKeyStore.apiKey()?.isEmpty == false else {
            presentNodeImageKeyInput()
            return
        }
        presentImagePicker()
    }

    private func presentNodeImageKeyInput() {
        let alert = UIAlertController(
            title: "填写 NodeImage API Key",
            message: "输入已有的 API Key 后即可发送图片。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "X-API-Key"
            field.textContentType = .password
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let key = NodeImageAPIKeyNormalizer.normalized(alert?.textFields?.first?.text ?? "")
            guard key.isEmpty == false else { return }
            self.nodeImageAPIKeyStore.save(apiKey: key)
            self.presentImagePicker()
        })
        present(alert, animated: true)
    }

    private func presentImagePicker() {
        let alert = UIAlertController(title: "发送图片", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "拍照", style: .default) { [weak self] _ in
                self?.presentCameraPicker()
            })
        }
        alert.addAction(UIAlertAction(title: "从相册选择", style: .default) { [weak self] _ in
            self?.presentPhotoLibraryPicker()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = imageButton
            popover.sourceRect = imageButton.bounds
        }
        present(alert, animated: true)
    }

    private func presentPhotoLibraryPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentCameraPicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentPhotoLibraryPicker()
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = self
        present(picker, animated: true)
    }

    private func uploadImage(data: Data, fileName: String, mimeType: String) {
        guard let apiKey = nodeImageAPIKeyStore.apiKey(), apiKey.isEmpty == false else {
            presentError("请先完成 NodeImage 授权。")
            return
        }

        imageUploadTask?.cancel()
        let uploader = nodeImageUploadClient
        imageUploadTask = Task { [weak self] in
            do {
                let payload = await Task.detached(priority: .userInitiated) {
                    NodeImageUploadImageCompressor.compressedPayload(
                        data: data,
                        fileName: fileName,
                        mimeType: mimeType
                    )
                }.value
                let result = try await uploader.uploadImage(
                    data: payload.data,
                    fileName: payload.fileName,
                    mimeType: payload.mimeType,
                    apiKey: apiKey
                )
                guard let self, Task.isCancelled == false else { return }
                messageTextView.insertSubmissionText(result.markdownText, separatedByNewlines: true)
                markdownSwitch.setOn(true, animated: true)
                messageTextView.becomeFirstResponder()
            } catch {
                guard let self, Task.isCancelled == false else { return }
                presentError(error.localizedDescription)
            }
            guard let self else { return }
            imageUploadTask = nil
            updateComposerState()
        }
        updateComposerState()
    }

    private func uploadPastedImage(_ image: UIImage) -> Bool {
        guard nodeImageAPIKeyStore.apiKey()?.isEmpty == false else {
            presentError("请先完成 NodeImage 授权。")
            return false
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            presentError("图片编码失败。")
            return false
        }
        uploadImage(
            data: data,
            fileName: "nodeseek-paste-\(Int(Date().timeIntervalSince1970)).jpg",
            mimeType: "image/jpeg"
        )
        return true
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension PrivateMessageViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: PrivateMessageCell.reuseIdentifier,
            for: indexPath
        ) as? PrivateMessageCell else {
            return UITableViewCell()
        }
        let message = messages[indexPath.row]
        cell.configure(
            message: message,
            isOutgoing: message.senderID == currentUserID,
            ownAvatarURL: currentUserAvatarURL,
            onLinkTap: { [weak self] url in
                self?.openMessageLink(url)
            }
        )
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard messages.indices.contains(indexPath.row),
              messages[indexPath.row].senderID == currentUserID else {
            return nil
        }
        let message = messages[indexPath.row]
        let editAction = UIAction(
            title: "编辑消息",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.beginEditing(message)
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [editAction])
        }
    }

    private func beginEditing(_ message: NodeSeekPrivateMessage) {
        editingMessageID = message.id
        messageTextView.text = message.content
        markdownSwitch.setOn(message.isMarkdown, animated: true)
        updateComposerState()
        messageTextView.becomeFirstResponder()
    }

    private func openMessageLink(_ url: URL) {
        guard let destination = PostDetailLinkResolver.destination(
            for: url,
            baseURL: NodeSeekSite.baseURL
        ) else {
            return
        }

        switch destination {
        case .nativePost(let postID, let page, let resolvedURL):
            let post = PostSummary(
                id: postID,
                title: "帖子 #\(postID)",
                url: resolvedURL,
                authorName: "",
                nodeName: nil,
                replyCount: 0,
                lastActivityText: nil
            )
            let anchorID = NodeSeekPostRouteResolver.route(
                for: resolvedURL,
                baseURL: NodeSeekSite.baseURL
            )?.anchorID
            showLinkedDestination(
                PostDetailRouter.createModule(
                    post: post,
                    page: page,
                    initialAnchorID: anchorID
                )
            )
        case .nativePrivateMessage(let participantID):
            showLinkedDestination(
                PrivateMessageViewController(
                    participantID: participantID,
                    participantName: "私信"
                )
            )
        case .userProfile(let profileURL):
            if let userID = NodeSeekUserIDResolver.uid(from: profileURL) {
                showLinkedDestination(ProfileTabViewController(userID: userID))
            } else {
                showLinkedDestination(NodeSeekWebViewController(url: profileURL))
            }
        case .web(let webURL):
            showLinkedDestination(NodeSeekWebViewController(url: webURL))
        case .currentPageAnchor:
            showLinkedDestination(NodeSeekWebViewController(url: url))
        case .safari(let safariURL):
            present(SFSafariViewController(url: safariURL), animated: true)
        case .externalApp(let externalURL):
            UIApplication.shared.open(externalURL, options: [:]) { [weak self] success in
                guard success == false else { return }
                DispatchQueue.main.async {
                    self?.presentError("无法打开这个链接。")
                }
            }
        }
    }

    private func showLinkedDestination(_ viewController: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
            return
        }
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
}

extension PrivateMessageViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateComposerState()
    }
}

extension PrivateMessageViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        let provider = result.itemProvider
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            presentError("所选文件不是图片。")
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data else {
                    self.presentError(error?.localizedDescription ?? "无法读取图片。")
                    return
                }
                let fileName = provider.suggestedName ?? "nodeseek-image.jpg"
                let type = UTType(filenameExtension: URL(fileURLWithPath: fileName).pathExtension) ?? .jpeg
                self.uploadImage(
                    data: data,
                    fileName: fileName,
                    mimeType: type.preferredMIMEType ?? "image/jpeg"
                )
            }
        }
    }
}

extension PrivateMessageViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.88) else {
            presentError("无法读取拍摄的图片。")
            return
        }
        uploadImage(data: data, fileName: "nodeseek-camera.jpg", mimeType: "image/jpeg")
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

private final class PrivateMessageCell: UITableViewCell {
    static let reuseIdentifier = "PrivateMessageCell"

    private let avatarImageView = UIImageView()
    private let bubbleView = UIView()
    private let contentTextView = UITextView()
    private let messageImageView = UIImageView()
    private let timeLabel = UILabel()
    private var imageHeightConstraint: NSLayoutConstraint!
    private var imageWidthConstraint: NSLayoutConstraint!
    private var labelBottomConstraint: NSLayoutConstraint!
    private var imageTopConstraint: NSLayoutConstraint!
    private var imageBottomConstraint: NSLayoutConstraint!
    private var leadingConstraints: [NSLayoutConstraint] = []
    private var trailingConstraints: [NSLayoutConstraint] = []
    private var representedID = 0
    private var messageImageURL: URL?
    private var onLinkTap: ((URL) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        AvatarImageLoader.shared.cancel(on: avatarImageView)
        representedID = 0
        contentTextView.attributedText = nil
        contentTextView.isUserInteractionEnabled = false
        timeLabel.text = nil
        messageImageView.image = nil
        messageImageURL = nil
        onLinkTap = nil
    }

    func configure(
        message: NodeSeekPrivateMessage,
        isOutgoing: Bool,
        ownAvatarURL: URL?,
        onLinkTap: @escaping (URL) -> Void
    ) {
        representedID = message.id
        self.onLinkTap = onLinkTap
        let avatarURL = isOutgoing ? ownAvatarURL : message.senderAvatarURL
        ImageLoad.url(avatarURL)
            .toAvatar(requestID: "message-\(isOutgoing ? "self" : String(message.senderID))")
            .into(avatarImageView)

        let imageURL = Self.markdownImageURL(in: message.content)
        messageImageURL = imageURL
        let renderedMessage = NodeSeekPrivateMessageMarkdownRenderer.render(message.content)
        contentTextView.attributedText = imageURL == nil
            ? renderedMessage.attributedText
            : NSAttributedString(string: "图片", attributes: Self.messageTextAttributes)
        contentTextView.isUserInteractionEnabled = true
        timeLabel.text = NodeSeekNotificationDateParser.displayText(from: message.createdAt)
        messageImageView.image = nil
        messageImageView.isHidden = imageURL == nil
        imageHeightConstraint.constant = imageURL == nil ? 0 : 164
        imageWidthConstraint.isActive = imageURL != nil
        labelBottomConstraint.isActive = imageURL == nil
        imageTopConstraint.isActive = imageURL != nil
        imageBottomConstraint.isActive = imageURL != nil

        NSLayoutConstraint.deactivate(leadingConstraints + trailingConstraints)
        NSLayoutConstraint.activate(isOutgoing ? trailingConstraints : leadingConstraints)
        bubbleView.backgroundColor = isOutgoing ? UIColor.systemOrange.withAlphaComponent(0.16) : .secondarySystemBackground
        contentTextView.textAlignment = .natural
        timeLabel.textAlignment = isOutgoing ? .right : .left

        if let imageURL {
            ImageLoad.url(imageURL)
                .toDetailInline(maxPixelWidth: 660, displayScale: UIScreen.main.scale)
                .load { [weak self] image in
                    DispatchQueue.main.async {
                        guard let self, self.representedID == message.id else { return }
                        guard let image else {
                            self.messageImageView.isHidden = true
                            self.imageWidthConstraint.isActive = false
                            self.imageHeightConstraint.constant = 0
                            self.imageTopConstraint.isActive = false
                            self.imageBottomConstraint.isActive = false
                            self.labelBottomConstraint.isActive = true
                            self.contentTextView.attributedText = Self.imageLoadFailureText(url: imageURL)
                            self.invalidateTableRowHeight()
                            return
                        }
                        self.messageImageView.image = image
                        self.messageImageView.isHidden = false
                        self.imageHeightConstraint.constant = self.imageDisplayHeight(for: image)
                        self.invalidateTableRowHeight()
                    }
                }
        }
    }

    private func setupUI() {
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 18
        avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarImageView.tintColor = .tertiaryLabel

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 14

        contentTextView.translatesAutoresizingMaskIntoConstraints = false
        contentTextView.backgroundColor = .clear
        contentTextView.font = .preferredFont(forTextStyle: .body)
        contentTextView.textColor = .label
        contentTextView.adjustsFontForContentSizeCategory = true
        contentTextView.isEditable = false
        contentTextView.isScrollEnabled = false
        contentTextView.isSelectable = true
        contentTextView.dataDetectorTypes = [.link]
        contentTextView.delegate = self
        contentTextView.textContainerInset = .zero
        contentTextView.textContainer.lineFragmentPadding = 0
        contentTextView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: 0
        ]

        messageImageView.translatesAutoresizingMaskIntoConstraints = false
        messageImageView.contentMode = .scaleAspectFit
        messageImageView.clipsToBounds = true
        messageImageView.layer.cornerRadius = 8
        messageImageView.isUserInteractionEnabled = true
        messageImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openMessageImage)))

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .preferredFont(forTextStyle: .caption2)
        timeLabel.textColor = .secondaryLabel
        timeLabel.adjustsFontForContentSizeCategory = true

        contentView.addSubview(avatarImageView)
        contentView.addSubview(bubbleView)
        contentView.addSubview(timeLabel)
        bubbleView.addSubview(contentTextView)
        bubbleView.addSubview(messageImageView)

        imageHeightConstraint = messageImageView.heightAnchor.constraint(equalToConstant: 0)
        imageWidthConstraint = messageImageView.widthAnchor.constraint(
            equalTo: contentView.widthAnchor,
            multiplier: 0.60
        )
        imageWidthConstraint.isActive = false
        labelBottomConstraint = contentTextView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -9)
        imageTopConstraint = messageImageView.topAnchor.constraint(equalTo: contentTextView.bottomAnchor, constant: 7)
        imageBottomConstraint = messageImageView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -9)
        imageTopConstraint.isActive = false
        imageBottomConstraint.isActive = false

        leadingConstraints = [
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            bubbleView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -58),
            timeLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor)
        ]
        trailingConstraints = [
            avatarImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            bubbleView.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8),
            bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 58),
            timeLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        ]

        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.68),

            contentTextView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 11),
            contentTextView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -11),
            contentTextView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 9),
            labelBottomConstraint,

            messageImageView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 11),
            messageImageView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -11),
            imageHeightConstraint,

            timeLabel.topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 4),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    private func imageDisplayHeight(for image: UIImage) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 164 }
        let width = contentView.bounds.width * 0.60
        guard width > 0 else { return 164 }
        return ceil(width * image.size.height / image.size.width)
    }

    private func invalidateTableRowHeight() {
        setNeedsLayout()
        superview?.superview?.setNeedsLayout()
        var ancestor = superview
        while let view = ancestor {
            if let tableView = view as? UITableView {
                tableView.performBatchUpdates(nil)
                return
            }
            ancestor = view.superview
        }
    }

    @objc private func openMessageImage() {
        guard let messageImageURL else { return }
        UIApplication.shared.open(messageImageURL)
    }

    fileprivate static var messageTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label
        ]
    }

    private static func imageLoadFailureText(url: URL) -> NSAttributedString {
        var attributes = messageTextAttributes
        attributes[.link] = url
        return NSAttributedString(
            string: "图片加载失败，轻点查看原图",
            attributes: attributes
        )
    }

    private static func markdownImageURL(in content: String) -> URL? {
        guard let imageStart = content.range(of: "!["),
              let altTextEnd = content[imageStart.upperBound...].firstIndex(of: "]"),
              content[altTextEnd...].hasPrefix("]("),
              let closing = content[altTextEnd...].firstIndex(of: ")") else {
            return nil
        }
        let urlStart = content.index(altTextEnd, offsetBy: 2)
        let value = String(content[urlStart..<closing])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? ""
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
    }
}

extension PrivateMessageCell: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        onLinkTap?(url)
        return false
    }
}

struct NodeSeekPrivateMessageMarkdownRenderer {
    struct RenderedMessage {
        let attributedText: NSAttributedString
        let hasLinks: Bool
    }

    static func render(_ content: String) -> RenderedMessage {
        let result = NSMutableAttributedString()
        var cursor = content.startIndex
        var hasLinks = false

        while let linkStart = content[cursor...].firstIndex(of: "[") {
            guard linkStart == content.startIndex || content[content.index(before: linkStart)] != "!",
                  let labelEnd = content[linkStart...].firstIndex(of: "]"),
                  content[labelEnd...].hasPrefix("]("),
                  let urlEnd = content[labelEnd...].firstIndex(of: ")") else {
                let next = content.index(after: linkStart)
                result.append(NSAttributedString(
                    string: String(content[cursor..<next]),
                    attributes: PrivateMessageCell.messageTextAttributes
                ))
                cursor = next
                continue
            }

            let urlStart = content.index(labelEnd, offsetBy: 2)
            let label = String(content[content.index(after: linkStart)..<labelEnd])
            let rawURL = String(content[urlStart..<urlEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .first
                .map(String.init) ?? ""
            guard label.isEmpty == false, let url = resolvedHTTPURL(rawURL) else {
                let next = content.index(after: linkStart)
                result.append(NSAttributedString(
                    string: String(content[cursor..<next]),
                    attributes: PrivateMessageCell.messageTextAttributes
                ))
                cursor = next
                continue
            }

            result.append(NSAttributedString(
                string: String(content[cursor..<linkStart]),
                attributes: PrivateMessageCell.messageTextAttributes
            ))
            var linkAttributes = PrivateMessageCell.messageTextAttributes
            linkAttributes[.link] = url
            result.append(NSAttributedString(string: label, attributes: linkAttributes))
            cursor = content.index(after: urlEnd)
            hasLinks = true
        }

        result.append(NSAttributedString(
            string: String(content[cursor...]),
            attributes: PrivateMessageCell.messageTextAttributes
        ))
        return RenderedMessage(attributedText: result, hasLinks: hasLinks)
    }

    private static func resolvedHTTPURL(_ rawURL: String) -> URL? {
        guard let url = URL(string: rawURL, relativeTo: NodeSeekSite.baseURL)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
    }
}
