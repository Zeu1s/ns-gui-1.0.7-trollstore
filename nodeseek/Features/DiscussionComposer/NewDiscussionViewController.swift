//
//  NewDiscussionViewController.swift
//  nodeseek
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class NewDiscussionViewController: UIViewController {
    private struct Category: Hashable {
        let code: String
        let title: String
    }

    private static let categories = [
        Category(code: "daily", title: "日常"),
        Category(code: "tech", title: "技术"),
        Category(code: "info", title: "情报"),
        Category(code: "review", title: "测评"),
        Category(code: "trade", title: "交易"),
        Category(code: "carpool", title: "拼车"),
        Category(code: "promotion", title: "推广"),
        Category(code: "life", title: "生活"),
        Category(code: "dev", title: "Dev"),
        Category(code: "photo-share", title: "贴图"),
        Category(code: "expose", title: "曝光"),
        Category(code: "inside", title: "内版"),
        Category(code: "meaningless", title: "无意义"),
        Category(code: "sandbox", title: "沙盒")
    ]

    private let client: NodeSeekDiscussionSubmitting
    private let nodeImageAPIKeyStore: NodeImageAPIKeyStoring
    private let nodeImageUploadClient: NodeImageUploading
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleField = UITextField()
    private let categoryButton = UIButton(type: .system)
    private let visibilityButton = UIButton(type: .system)
    private let editorTextView = FormattingTextView()
    private let editorPlaceholderLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var selectedCategory = NewDiscussionViewController.categories[0]
    private var selectedRank = 0
    private var isSubmitting = false
    private var imageUploadTask: Task<Void, Never>?

    init(
        client: NodeSeekDiscussionSubmitting = NodeSeekDiscussionClient(),
        nodeImageAPIKeyStore: NodeImageAPIKeyStoring = KeychainNodeImageAPIKeyStore(),
        nodeImageUploadClient: NodeImageUploading = NodeImageUploadClient()
    ) {
        self.client = client
        self.nodeImageAPIKeyStore = nodeImageAPIKeyStore
        self.nodeImageUploadClient = nodeImageUploadClient
        super.init(nibName: nil, bundle: nil)
        title = "发帖"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        imageUploadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigation()
        configureForm()
        updateCategoryButtonTitle()
        updateVisibilityButtonTitle()
    }

    private func configureNavigation() {
        let submit = UIBarButtonItem(title: "发布", style: .done, target: self, action: #selector(submitTapped))
        submit.accessibilityIdentifier = "new-discussion-submit-button"
        navigationItem.rightBarButtonItem = submit
        navigationItem.largeTitleDisplayMode = .never
    }

    private func configureForm() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        titleField.placeholder = "请输入标题"
        titleField.font = .preferredFont(forTextStyle: .title3)
        titleField.textColor = .label
        titleField.borderStyle = .none
        titleField.clearButtonMode = .whileEditing
        titleField.returnKeyType = .next
        titleField.delegate = self
        titleField.accessibilityLabel = "帖子标题"
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let titleContainer = UIView()
        titleContainer.backgroundColor = .secondarySystemBackground
        titleContainer.layer.cornerRadius = 8
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(titleField)
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -12),
            titleField.topAnchor.constraint(equalTo: titleContainer.topAnchor, constant: 4),
            titleField.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: -4),
            titleContainer.heightAnchor.constraint(equalToConstant: 46)
        ])

        configureMenuButton(categoryButton, icon: "square.grid.2x2", action: #selector(categoryTapped))
        categoryButton.accessibilityIdentifier = "new-discussion-category-button"
        configureMenuButton(visibilityButton, icon: "eye", action: #selector(visibilityTapped))
        visibilityButton.accessibilityIdentifier = "new-discussion-visibility-button"

        let menuStack = UIStackView(arrangedSubviews: [categoryButton, visibilityButton])
        menuStack.axis = .horizontal
        menuStack.spacing = 10
        menuStack.distribution = .fillEqually
        menuStack.translatesAutoresizingMaskIntoConstraints = false

        editorTextView.backgroundColor = .secondarySystemBackground
        editorTextView.textColor = .label
        editorTextView.font = .preferredFont(forTextStyle: .body)
        editorTextView.adjustsFontForContentSizeCategory = true
        editorTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        editorTextView.layer.cornerRadius = 8
        editorTextView.delegate = self
        editorTextView.accessibilityLabel = "帖子内容"
        editorTextView.translatesAutoresizingMaskIntoConstraints = false

        editorPlaceholderLabel.text = "写下想分享的内容..."
        editorPlaceholderLabel.font = .preferredFont(forTextStyle: .body)
        editorPlaceholderLabel.textColor = .placeholderText
        editorPlaceholderLabel.numberOfLines = 0
        editorPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        editorTextView.addSubview(editorPlaceholderLabel)
        NSLayoutConstraint.activate([
            editorPlaceholderLabel.leadingAnchor.constraint(equalTo: editorTextView.leadingAnchor, constant: 14),
            editorPlaceholderLabel.trailingAnchor.constraint(equalTo: editorTextView.trailingAnchor, constant: -14),
            editorPlaceholderLabel.topAnchor.constraint(equalTo: editorTextView.topAnchor, constant: 12),
            editorTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        let imageItem = UIBarButtonItem(
            image: UIImage(systemName: "photo"),
            style: .plain,
            target: self,
            action: #selector(imageTapped)
        )
        imageItem.accessibilityLabel = "插入图片"
        let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
        let editorToolbar = UIToolbar()
        editorToolbar.items = [imageItem, spacer]
        editorToolbar.sizeToFit()
        editorTextView.inputAccessoryView = editorToolbar

        let helperLabel = UILabel()
        helperLabel.text = "支持 Markdown 和图片链接"
        helperLabel.font = .preferredFont(forTextStyle: .footnote)
        helperLabel.textColor = .secondaryLabel
        helperLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleContainer)
        contentView.addSubview(menuStack)
        contentView.addSubview(editorTextView)
        contentView.addSubview(helperLabel)
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            titleContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),

            menuStack.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            menuStack.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
            menuStack.topAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: 12),
            menuStack.heightAnchor.constraint(equalToConstant: 42),

            editorTextView.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            editorTextView.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
            editorTextView.topAnchor.constraint(equalTo: menuStack.bottomAnchor, constant: 12),

            helperLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            helperLabel.topAnchor.constraint(equalTo: editorTextView.bottomAnchor, constant: 8),
            helperLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureMenuButton(_ button: UIButton, icon: String, action: Selector) {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: icon)
        configuration.imagePadding = 7
        configuration.imagePlacement = .leading
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.cornerStyle = .fixed
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func categoryTapped() {
        let alert = UIAlertController(title: "选择板块", message: nil, preferredStyle: .actionSheet)
        Self.categories.forEach { category in
            alert.addAction(UIAlertAction(title: category.title, style: .default) { [weak self] _ in
                self?.selectedCategory = category
                self?.updateCategoryButtonTitle()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentActionSheet(alert, from: categoryButton)
    }

    @objc private func visibilityTapped() {
        let alert = UIAlertController(title: "阅读限制", message: nil, preferredStyle: .actionSheet)
        let options = [(0, "公开")]
            + (1...10).map { ($0, "Lv \($0)") }
            + [(255, "私有")]
        options.forEach { rank, title in
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.selectedRank = rank
                self?.updateVisibilityButtonTitle()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentActionSheet(alert, from: visibilityButton)
    }

    @objc private func imageTapped() {
        if nodeImageAPIKeyStore.apiKey()?.isEmpty == false {
            presentPhotoLibraryPicker()
            return
        }
        presentNodeImageKeyInput()
    }

    @objc private func submitTapped() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = editorTextView.formattedSubmissionText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            presentError("标题不能为空。")
            return
        }
        guard content.isEmpty == false else {
            presentError("帖子内容不能为空。")
            return
        }
        guard isSubmitting == false else { return }

        let draft = NodeSeekDiscussionDraft(
            title: title,
            content: content,
            category: selectedCategory.code,
            rank: selectedRank
        )
        if selectedCategory.code == "inside" {
            confirmInsideDiscussionSubmission(draft, title: title)
            return
        }
        submit(draft, title: title)
    }

    private func confirmInsideDiscussionSubmission(_ draft: NodeSeekDiscussionDraft, title: String) {
        let alert = UIAlertController(
            title: "确认发内版",
            message: "发内版需要消耗 5 个鸡腿。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "继续", style: .default) { [weak self] _ in
            self?.submit(draft, title: title)
        })
        present(alert, animated: true)
    }

    private func submit(_ draft: NodeSeekDiscussionDraft, title: String) {
        setSubmitting(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let submission = try await client.submit(draft)
                guard Task.isCancelled == false else { return }
                setSubmitting(false)
                showSubmittedDiscussion(submission, title: title)
            } catch {
                guard Task.isCancelled == false else { return }
                setSubmitting(false)
                if case .notLoggedIn = error as? NodeSeekDiscussionClientError {
                    presentLoginRequired()
                } else {
                    presentError(error.localizedDescription)
                }
            }
        }
    }

    private func updateCategoryButtonTitle() {
        var configuration = categoryButton.configuration
        configuration?.title = selectedCategory.title
        categoryButton.configuration = configuration
    }

    private func updateVisibilityButtonTitle() {
        var configuration = visibilityButton.configuration
        configuration?.title = switch selectedRank {
        case 255:
            "私有"
        case 0:
            "公开"
        default:
            "Lv \(selectedRank)"
        }
        visibilityButton.configuration = configuration
    }

    private func setSubmitting(_ submitting: Bool) {
        isSubmitting = submitting
        titleField.isEnabled = !submitting
        categoryButton.isEnabled = !submitting
        visibilityButton.isEnabled = !submitting
        editorTextView.isEditable = !submitting
        navigationItem.rightBarButtonItem?.isEnabled = !submitting
        submitting ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
    }

    private func showSubmittedDiscussion(_ submission: NodeSeekDiscussionSubmission, title: String) {
        guard let url = destinationURL(for: submission),
              let route = NodeSeekPostRouteResolver.route(for: url, baseURL: NodeSeekSite.baseURL) else {
            let alert = UIAlertController(title: "发布成功", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })
            present(alert, animated: true)
            return
        }

        let post = PostSummary(
            id: route.postID,
            title: title,
            url: route.url,
            authorName: "",
            nodeName: selectedCategory.title,
            replyCount: 0,
            lastActivityText: nil
        )
        navigationController?.pushViewController(
            PostDetailRouter.createModule(post: post, page: route.page, initialAnchorID: route.anchorID),
            animated: true
        )
    }

    private func destinationURL(for submission: NodeSeekDiscussionSubmission) -> URL? {
        guard let redirect = submission.redirect,
              let url = URL(string: redirect, relativeTo: NodeSeekSite.baseURL)?.absoluteURL else {
            return nil
        }
        guard let hash = submission.redirectHash, hash.isEmpty == false else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = hash.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return components?.url ?? url
    }

    private func presentLoginRequired() {
        let alert = UIAlertController(title: "需要登录", message: "发帖需要先完成 NodeSeek 登录。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "去登录", style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(LoginWebViewController(), animated: true)
        })
        present(alert, animated: true)
    }

    private func presentNodeImageKeyInput() {
        let alert = UIAlertController(
            title: "填写 NodeImage API Key",
            message: "输入已有的 API Key 后即可插入图片。",
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
            self.presentPhotoLibraryPicker()
        })
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

    private func uploadImage(data: Data, fileName: String, mimeType: String) {
        guard let apiKey = nodeImageAPIKeyStore.apiKey(), apiKey.isEmpty == false else { return }
        imageUploadTask?.cancel()
        navigationItem.rightBarButtonItem?.isEnabled = false
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
                editorTextView.insertSubmissionText(result.markdownText, separatedByNewlines: true)
                editorPlaceholderLabel.isHidden = true
            } catch {
                guard let self, Task.isCancelled == false else { return }
                presentError(error.localizedDescription)
            }
            guard let self else { return }
            imageUploadTask = nil
            navigationItem.rightBarButtonItem?.isEnabled = !isSubmitting
        }
    }

    private func presentActionSheet(_ alert: UIAlertController, from sourceView: UIView) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        present(alert, animated: true)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension NewDiscussionViewController: UITextFieldDelegate, UITextViewDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        editorTextView.becomeFirstResponder()
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        editorPlaceholderLabel.isHidden = textView.text.isEmpty == false
    }
}

extension NewDiscussionViewController: PHPickerViewControllerDelegate {
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
                self.uploadImage(data: data, fileName: fileName, mimeType: type.preferredMIMEType ?? "image/jpeg")
            }
        }
    }
}
