//
//  DiscussionEditViewController.swift
//  nodeseek
//

import UIKit

private struct NodeSeekDiscussionEditSnapshot: Sendable {
    let editorURL: URL
    let title: String
    let content: String
    let titleFieldName: String?
    let contentFieldName: String?
    let rank: Int
    let rankFieldName: String?
}

private enum NodeSeekDiscussionEditError: LocalizedError {
    case unavailable(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .invalidResponse:
            return "编辑页面返回的数据无法识别。"
        }
    }
}

/// 编辑入口和提交地址均由 NodeSeek 当前页面实时发现，避免把不稳定的网页接口固化到 App 中。
private final class NodeSeekDiscussionEditClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func loadEditor(postURL: URL) async throws -> NodeSeekDiscussionEditSnapshot {
        let result = try await withHiddenWebViewPageActionLoader(
            logMessage: "准备读取主题编辑表单: \(postURL.absoluteString)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: postURL,
                source: Self.loadEditorScript,
                arguments: [:],
                timeoutInterval: self.timeoutInterval,
                actionName: "读取主题编辑表单"
            )
        }
        guard result["ok"] as? Bool == true else {
            throw NodeSeekDiscussionEditError.unavailable(
                result["message"] as? String ?? "当前帖子没有可用的编辑入口。"
            )
        }
        guard let editorURLText = result["editorURL"] as? String,
              let editorURL = URL(string: editorURLText),
              let content = result["content"] as? String else {
            throw NodeSeekDiscussionEditError.invalidResponse
        }
        let rank = (result["rank"] as? NSNumber)?.intValue ?? 0
        return NodeSeekDiscussionEditSnapshot(
            editorURL: editorURL,
            title: result["title"] as? String ?? "",
            content: content,
            titleFieldName: result["titleFieldName"] as? String,
            contentFieldName: result["contentFieldName"] as? String,
            rank: max(0, rank),
            rankFieldName: result["rankFieldName"] as? String
        )
    }
    func submit(
        snapshot: NodeSeekDiscussionEditSnapshot,
        title: String,
        content: String,
        rank: Int
    ) async throws {
        let result = try await withHiddenWebViewPageActionLoader(
            logMessage: "准备提交主题编辑: \(snapshot.editorURL.absoluteString)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: snapshot.editorURL,
                source: Self.submitEditorScript,
                arguments: [
                    "title": title,
                    "content": content,
                    "titleFieldName": snapshot.titleFieldName ?? "",
                    "contentFieldName": snapshot.contentFieldName ?? "",
                    "rank": rank,
                    "rankFieldName": snapshot.rankFieldName ?? ""
                ],
                timeoutInterval: self.timeoutInterval,
                actionName: "提交主题编辑"
            )
        }
        guard result["ok"] as? Bool == true else {
            throw NodeSeekDiscussionEditError.unavailable(
                result["message"] as? String ?? "主题保存失败，请稍后重试。"
            )
        }
    }

    private static let loadEditorScript = """
    return await new Promise(async (resolve) => {
      const visible = (element) => {
        if (!element) return false;
        const style = window.getComputedStyle(element);
        return style.display !== 'none' && style.visibility !== 'hidden';
      };
      const textOf = (element) => (element.innerText || element.textContent || element.value || '').trim();
      const isEditLink = (element) => {
        const href = String(element.getAttribute('href') || '');
        const text = textOf(element);
        return /编辑|修改|edit|modify|update/i.test(text + ' ' + href) && !href.startsWith('javascript:');
      };
      const findForm = (documentRoot) => {
        const forms = Array.from(documentRoot.querySelectorAll('form'));
        return forms.find((form) => form.querySelector('input[name*="title" i]') && form.querySelector('textarea, [contenteditable="true"], input[name*="content" i]'))
          || forms.find((form) => form.querySelector('textarea, [contenteditable="true"], input[name*="content" i]')) || null;
      };
      const findTitle = (form) => form && (
        form.querySelector('input[name=\"title\" i]') ||
        form.querySelector('input[name*=\"title\" i]') ||
        form.querySelector('input[type=\"text\"]')
      );
      const findContent = (form) => form && (
        form.querySelector('textarea[name=\"content\" i]') ||
        form.querySelector('textarea[name*=\"content\" i]') ||
        form.querySelector('textarea') ||
        form.querySelector('[contenteditable=\"true\"]')
      );
      const isEditorForm = (form) => {
        if (!form) return false;
        const contentField = findContent(form);
        if (!contentField) return false;
        if (form.querySelector('input[name*="title" i]')) return true;
        const name = String(contentField.name || '').toLowerCase();
        return name.includes('content') && /edit|modify|update/i.test(String(form.getAttribute('action') || ''));
      };
      const findRank = (form) => form && (
        form.querySelector('select[name*="rank" i], select[name*="level" i], input[type="radio"][name*="rank" i], input[type="radio"][name*="level" i]')
      );
      try {
        let editorURL = window.location.href;
        let editorDocument = document;
        let form = findForm(editorDocument);
        if (!isEditorForm(form)) {
          const entry = Array.from(document.querySelectorAll('a, button')).find((element) => visible(element) && isEditLink(element));
          const href = entry && entry.getAttribute('href');
          if (!href) {
            resolve({ ok: false, reason: 'editor_entry_not_found', message: '当前帖子未提供编辑入口。' });
            return;
          }
          editorURL = new URL(href, window.location.href).href;
          const response = await fetch(editorURL, { credentials: 'same-origin' });
          const html = await response.text();
          if (!response.ok) {
            resolve({ ok: false, reason: 'editor_page_failed', message: '无法打开主题编辑页面。' });
            return;
          }
          editorDocument = new DOMParser().parseFromString(html, 'text/html');
          form = findForm(editorDocument);
        }
        const title = findTitle(form);
        const content = findContent(form);
        if (!form || !content || !isEditorForm(form)) {
          resolve({ ok: false, reason: 'editor_form_not_found', message: '未找到可编辑的主题内容。' });
          return;
        }
        const contentValue = 'value' in content ? content.value : (content.textContent || '');
        const rankField = findRank(form);
        let rank = 0;
        let rankFieldName = '';
        if (rankField) {
          rankFieldName = rankField.name || '';
          if (rankField.type === 'radio') {
            const checked = editorDocument.querySelector('input[type="radio"][name="' + CSS.escape(rankField.name) + '"]:checked');
            rank = parseInt((checked || rankField).value, 10) || 0;
          } else {
            rank = parseInt(rankField.value, 10) || 0;
          }
        }
        resolve({
          ok: true,
          editorURL,
          title: title ? (title.value || '') : '',
          content: contentValue,
          titleFieldName: title ? (title.name || '') : '',
          contentFieldName: content.name || '',
          rank: rank,
          rankFieldName: rankFieldName
        });
      } catch (error) {
        resolve({ ok: false, reason: 'javascript_exception', message: String(error && error.message ? error.message : error) });
      }
    """

    private static let submitEditorScript = """
    return await new Promise(async (resolve) => {
      const nextTitle = title || '';
      const nextContent = content || '';
      const nextRank = String(rank == null ? '' : rank);
      const nextRankFieldName = rankFieldName || '';
      const findForm = () => Array.from(document.querySelectorAll('form')).find((form) => form.querySelector('textarea, [contenteditable=\"true\"], input[name*=\"content\" i]')) || null;
      const valueSetter = (element, value) => {
        if (!element) return;
        if ('value' in element) {
          const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element), 'value');
          if (descriptor && descriptor.set) descriptor.set.call(element, value); else element.value = value;
        } else {
          element.textContent = value;
        }
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
      };
      try {
        const form = findForm();
        if (!form) {
          resolve({ ok: false, reason: 'editor_form_not_found', message: '主题编辑表单已失效，请重新打开编辑。' });
          return;
        }
        const titleField = titleFieldName ? form.querySelector('[name="' + CSS.escape(titleFieldName) + '"]') : (form.querySelector('input[name=\"title\" i]') || form.querySelector('input[name*=\"title\" i]'));
        const contentField = contentFieldName ? form.querySelector('[name="' + CSS.escape(contentFieldName) + '"]') : (form.querySelector('textarea[name=\"content\" i]') || form.querySelector('textarea[name*=\"content\" i]') || form.querySelector('textarea') || form.querySelector('[contenteditable=\"true\"]'));
        if (!contentField) {
          resolve({ ok: false, reason: 'content_field_not_found', message: '主题内容输入框已失效，请重新打开编辑。' });
          return;
        }
        valueSetter(titleField, nextTitle);
        valueSetter(contentField, nextContent);
        const body = new FormData(form);
        if (titleFieldName) body.set(titleFieldName, nextTitle);
        if (contentFieldName) body.set(contentFieldName, nextContent);
        if (nextRankFieldName) {
          const rankInput = form.querySelector('[name="' + CSS.escape(nextRankFieldName) + '"]');
          if (rankInput) {
            if (rankInput.type === 'radio') {
              const target = Array.from(form.querySelectorAll('input[type="radio"][name="' + CSS.escape(nextRankFieldName) + '"]')).find((item) => String(item.value) === nextRank);
              if (target) {
                target.checked = true;
                target.dispatchEvent(new Event('change', { bubbles: true }));
              }
            } else {
              const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(rankInput), 'value');
              if (descriptor && descriptor.set) descriptor.set.call(rankInput, nextRank); else rankInput.value = nextRank;
              rankInput.dispatchEvent(new Event('input', { bubbles: true }));
              rankInput.dispatchEvent(new Event('change', { bubbles: true }));
            }
            body.set(nextRankFieldName, nextRank);
          }
        }
        const action = new URL(form.getAttribute('action') || window.location.href, window.location.href).href;
        const method = (form.getAttribute('method') || 'POST').toUpperCase();
        const response = await fetch(action, { method, body, credentials: 'same-origin' });
        const responseText = await response.text();
        let message = '';
        let explicitlyFailed = false;
        try {
          const json = JSON.parse(responseText || '{}');
          message = json.message || json.error || json.msg || '';
          explicitlyFailed = json.success === false || json.ok === false;
        } catch (_) {}
        resolve({
          ok: response.ok && !explicitlyFailed,
          statusCode: response.status,
          reason: response.ok && !explicitlyFailed ? 'submitted' : 'server_error',
          message: message || (response.ok ? '' : '主题保存失败。')
        });
      } catch (error) {
        resolve({ ok: false, reason: 'javascript_exception', message: String(error && error.message ? error.message : error) });
      }
    });
    """
}

@MainActor
final class DiscussionEditViewController: UIViewController, UITextViewDelegate {
    private let post: PostSummary
    private let client: NodeSeekDiscussionEditClient
    private let onSaved: () -> Void
    private let titleField = UITextField()
    private let visibilityButton = UIButton(type: .system)
    private let editorTextView = FormattingTextView()
    private let placeholderLabel = UILabel()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var snapshot: NodeSeekDiscussionEditSnapshot?
    private var loadingTask: Task<Void, Never>?
    private var isSaving = false
    private var selectedRank = 0

    init(
        post: PostSummary,

        onSaved: @escaping () -> Void
    ) {
        self.post = post
        self.client = NodeSeekDiscussionEditClient()
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
        title = "编辑主题"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadingTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigation()
        configureForm()
        updateVisibilityButtonTitle()
        titleField.text = post.title
        loadEditorContent()
    }

    private func configureNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "取消",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "保存",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    private func configureForm() {
        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        let titleLabel = UILabel()
        titleLabel.text = "标题"
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        titleField.borderStyle = .roundedRect
        titleField.font = .preferredFont(forTextStyle: .body)
        titleField.clearButtonMode = .whileEditing
        titleField.autocapitalizationType = .none
        titleField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        titleField.translatesAutoresizingMaskIntoConstraints = false

        var visibilityConfiguration = UIButton.Configuration.tinted()
        visibilityConfiguration.image = UIImage(systemName: "eye")
        visibilityConfiguration.imagePadding = 7
        visibilityConfiguration.imagePlacement = .leading
        visibilityConfiguration.baseForegroundColor = .label
        visibilityConfiguration.baseBackgroundColor = .secondarySystemBackground
        visibilityConfiguration.cornerStyle = .fixed
        visibilityButton.configuration = visibilityConfiguration
        visibilityButton.contentHorizontalAlignment = .leading
        visibilityButton.addTarget(self, action: #selector(visibilityTapped), for: .touchUpInside)
        visibilityButton.accessibilityLabel = "阅读限制"
        visibilityButton.translatesAutoresizingMaskIntoConstraints = false

        let contentLabel = UILabel()
        contentLabel.text = "内容"
        contentLabel.font = .preferredFont(forTextStyle: .subheadline)
        contentLabel.textColor = .secondaryLabel
        contentLabel.translatesAutoresizingMaskIntoConstraints = false

        editorTextView.font = .preferredFont(forTextStyle: .body)
        editorTextView.textColor = .label
        editorTextView.backgroundColor = .secondarySystemBackground
        editorTextView.layer.cornerRadius = 8
        editorTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        editorTextView.delegate = self
        editorTextView.isEditable = false
        editorTextView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.text = "正在读取原始内容..."
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        editorTextView.addSubview(placeholderLabel)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(titleField)
        contentView.addSubview(visibilityButton)
        contentView.addSubview(contentLabel)
        contentView.addSubview(editorTextView)
        contentView.addSubview(statusLabel)
        contentView.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            titleField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            titleField.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            visibilityButton.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),
            visibilityButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            visibilityButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            visibilityButton.heightAnchor.constraint(equalToConstant: 40),
            contentLabel.topAnchor.constraint(equalTo: visibilityButton.bottomAnchor, constant: 18),
            contentLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            editorTextView.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 7),
            editorTextView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            editorTextView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            editorTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            placeholderLabel.leadingAnchor.constraint(equalTo: editorTextView.leadingAnchor, constant: 14),
            placeholderLabel.trailingAnchor.constraint(equalTo: editorTextView.trailingAnchor, constant: -14),
            placeholderLabel.topAnchor.constraint(equalTo: editorTextView.topAnchor, constant: 12),
            statusLabel.topAnchor.constraint(equalTo: editorTextView.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: activityIndicator.leadingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            activityIndicator.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
    }

    @objc private func visibilityTapped() {
        let alert = UIAlertController(title: "阅读限制", message: nil, preferredStyle: .actionSheet)
        let options = [(0, "公开")]
            + (1...6).map { ($0, "Lv \($0)") }
            + [(255, "私有")]
        options.forEach { rank, title in
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.selectedRank = rank
                self?.updateVisibilityButtonTitle()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = visibilityButton
            popover.sourceRect = visibilityButton.bounds
        }
        present(alert, animated: true)
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

    private func loadEditorContent() {
        statusLabel.text = "正在读取可编辑内容"
        loadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await client.loadEditor(postURL: post.url)
                guard Task.isCancelled == false else { return }
                self.snapshot = snapshot
                self.titleField.text = snapshot.title.isEmpty ? self.post.title : snapshot.title
                self.editorTextView.text = snapshot.content
                self.editorTextView.isEditable = true
                self.placeholderLabel.isHidden = self.editorTextView.text.isEmpty == false
                self.selectedRank = snapshot.rank
                self.visibilityButton.isEnabled = snapshot.rankFieldName?.isEmpty == false
                self.updateVisibilityButtonTitle()
                self.statusLabel.text = ""
                self.activityIndicator.stopAnimating()
                self.updateSaveButton()
            } catch {
                guard Task.isCancelled == false else { return }
                self.statusLabel.text = error.localizedDescription
                self.activityIndicator.stopAnimating()
                self.placeholderLabel.text = "未能读取原始内容"
            }
        }
    }

    @objc private func textDidChange() {
        updateSaveButton()
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = textView.text.isEmpty == false
        updateSaveButton()
    }

    @objc private func cancelTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func saveTapped() {
        guard let snapshot else { return }
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = editorTextView.formattedSubmissionText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, content.isEmpty == false else {
            statusLabel.text = "标题和内容不能为空。"
            return
        }
        setSaving(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.submit(snapshot: snapshot, title: title, content: content, rank: selectedRank)
                self.onSaved()
                self.navigationController?.popViewController(animated: true)
            } catch {
                self.statusLabel.text = error.localizedDescription
                self.setSaving(false)
            }
        }
    }

    private func updateSaveButton() {
        guard isSaving == false else { return }
        let hasTitle = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasContent = editorTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        navigationItem.rightBarButtonItem?.isEnabled = snapshot != nil && hasTitle && hasContent
    }

    private func setSaving(_ isSaving: Bool) {
        self.isSaving = isSaving
        titleField.isEnabled = !isSaving
        visibilityButton.isEnabled = !isSaving && snapshot?.rankFieldName?.isEmpty == false
        editorTextView.isEditable = !isSaving
        navigationItem.leftBarButtonItem?.isEnabled = !isSaving
        navigationItem.rightBarButtonItem?.isEnabled = !isSaving
        statusLabel.text = isSaving ? "正在保存" : statusLabel.text
        if isSaving {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
            updateSaveButton()
        }
    }
}
