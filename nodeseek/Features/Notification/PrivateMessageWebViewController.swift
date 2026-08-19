//
//  PrivateMessageWebViewController.swift
//  nodeseek
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Keeps NodeSeek's private-message page as a web page while adding the app's
/// existing NodeImage upload flow directly to a conversation's text editor.
final class PrivateMessageWebViewController: BaseWebViewController {
    private let nodeImageAPIKeyStore: NodeImageAPIKeyStoring
    private let nodeImageUploadClient: NodeImageUploading
    private var imageUploadTask: Task<Void, Never>?
    private var isPrivateMessagePage = false

    private lazy var imageUploadButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "photo.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(uploadImageTapped)
        )
        button.accessibilityLabel = "通过图床发送图片"
        return button
    }()

    override var usesCustomUserAgent: Bool {
        false
    }

    init(
        url: URL,
        nodeImageAPIKeyStore: NodeImageAPIKeyStoring = KeychainNodeImageAPIKeyStore(),
        nodeImageUploadClient: NodeImageUploading = NodeImageUploadClient()
    ) {
        self.nodeImageAPIKeyStore = nodeImageAPIKeyStore
        self.nodeImageUploadClient = nodeImageUploadClient
        super.init(
            initialURL: url,
            pageTitle: "私信",
            additionalUserScripts: [Self.makeFloatingUploadButtonScript()]
        )
        isPrivateMessagePage = Self.isPrivateMessageURL(url)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        imageUploadTask?.cancel()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nodeSeekUploadImage")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.configuration.userContentController.add(self, name: "nodeSeekUploadImage")
    }

    override func configureNavigationItems() {
        super.configureNavigationItems()
        let moreButton = navigationItem.rightBarButtonItem
        navigationItem.rightBarButtonItems = [imageUploadButton, moreButton].compactMap { $0 }
        updateImageUploadButton()
    }

    override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        super.webView(webView, didFinish: navigation)
        isPrivateMessagePage = Self.isPrivateMessageURL(webView.url ?? initialURL)
        updateImageUploadButton()
    }

    @objc private func uploadImageTapped() {
        guard isPrivateMessagePage else {
            showAlert(message: "请先进入私信页面，再发送图片。")
            return
        }

        if nodeImageAPIKeyStore.apiKey()?.isEmpty == false {
            presentPhotoLibraryPicker()
            return
        }

        let authorizationViewController = NodeImageAuthViewController { [weak self] apiKey in
            guard let self else { return }
            self.nodeImageAPIKeyStore.save(apiKey: apiKey)
            self.dismiss(animated: true) { [weak self] in
                self?.presentPhotoLibraryPicker()
            }
        }
        present(UINavigationController(rootViewController: authorizationViewController), animated: true)
    }

    private func presentPhotoLibraryPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func uploadPickedImage(data: Data, fileName: String, mimeType: String) {
        guard let apiKey = nodeImageAPIKeyStore.apiKey(), apiKey.isEmpty == false else {
            showAlert(message: "请先完成 NodeImage 授权。")
            return
        }

        setImageUploadInProgress(true)
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
                await MainActor.run { [weak self] in
                    self?.insertMarkdownIntoMessageEditor(result.markdownText)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.showAlert(message: error.localizedDescription)
                }
            }
            await MainActor.run { [weak self] in
                self?.imageUploadTask = nil
                self?.setImageUploadInProgress(false)
            }
        }
    }

    private func insertMarkdownIntoMessageEditor(_ markdown: String) {
        webView.evaluateJavaScript(Self.insertMarkdownJavaScript(markdown)) { [weak self] result, error in
            guard let self else { return }
            guard error == nil, (result as? Bool) == true else {
                UIPasteboard.general.string = markdown
                self.showAlert(message: "图片已上传，链接已复制。请点按私信输入框后粘贴发送。")
                return
            }
        }
    }

    private func setImageUploadInProgress(_ inProgress: Bool) {
        imageUploadButton.isEnabled = !inProgress && isPrivateMessagePage
        imageUploadButton.image = UIImage(systemName: inProgress ? "arrow.up.circle" : "photo.badge.plus")
        imageUploadButton.accessibilityLabel = inProgress ? "正在上传图片" : "通过图床发送图片"
    }

    private func updateImageUploadButton() {
        imageUploadButton.isEnabled = isPrivateMessagePage && imageUploadTask == nil
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private static func makeFloatingUploadButtonScript() -> WKUserScript {
        WKUserScript(
            source: """
            (() => {
              const host = window.location.hostname.toLowerCase();
              if (host !== 'nodeseek.com' && !host.endsWith('.nodeseek.com')) return;
              const ensureButton = () => {
                if (document.getElementById('nodeseek-upload-image-button')) return;
                const route = (window.location.pathname + window.location.hash).toLowerCase();
                if (!route.includes('/message')) return;
                if (!document.documentElement) return;
                const button = document.createElement('button');
                button.id = 'nodeseek-upload-image-button';
                button.type = 'button';
                button.setAttribute('aria-label', '通过图床发送图片');
                button.title = '通过图床发送图片';
                button.textContent = '📷';
                button.style.cssText = 'display:inline-flex;align-items:center;justify-content:center;width:30px;height:30px;border-radius:50%;border:none;background:#1677ff;color:#fff;font-size:16px;line-height:1;margin-left:8px;vertical-align:middle;cursor:pointer;touch-action:manipulation;flex:0 0 auto';
                button.addEventListener('click', () => {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nodeSeekUploadImage) {
                    window.webkit.messageHandlers.nodeSeekUploadImage.postMessage({});
                  }
                });
                const selectors = [
                  '.layui-layer-title',
                  '[class*="conversation"] [class*="header"]',
                  '[class*="chat"] [class*="header"]',
                  '[class*="dialog"] [class*="header"]',
                  '[class*="message"] [class*="header"]',
                  '[class*="talk"] [class*="header"]',
                  '[class*="title-bar"]',
                  '[class*="user-name"]',
                  '[class*="username"]',
                  '[class*="nickname"]'
                ];
                const header = selectors
                  .map((selector) => document.querySelector(selector))
                  .find((el) => el && el.offsetParent !== null && el.textContent.trim().length > 0);
                if (header && header.parentElement) {
                  header.parentElement.appendChild(button);
                } else {
                  button.style.cssText = 'position:fixed;top:max(12px, env(safe-area-inset-top) + 64px);right:max(12px, env(safe-area-inset-right));width:44px;height:44px;border-radius:22px;border:none;background:#1677ff;color:#fff;font-size:20px;display:flex;align-items:center;justify-content:center;line-height:1;box-shadow:0 4px 12px rgba(0,0,0,0.25);z-index:2147483647;touch-action:manipulation';
                  document.documentElement.appendChild(button);
                }
              };
              const tryEnsure = () => { if (document.documentElement) { ensureButton(); } };
              tryEnsure();
              window.addEventListener('load', tryEnsure);
              const observer = new MutationObserver(tryEnsure);
              observer.observe(document.documentElement, { childList: true, subtree: true });
              window.addEventListener('hashchange', tryEnsure);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    private static func isPrivateMessageURL(_ url: URL) -> Bool {
        url.absoluteString.lowercased().contains("/message")
    }

    private static func insertMarkdownJavaScript(_ markdown: String) -> String {
        let encoded = (try? JSONEncoder().encode(markdown))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "\"\""
        return """
        (() => {
          const inserted = \(encoded);
          const active = document.activeElement;
          const candidates = [
            active,
            ...Array.from(document.querySelectorAll('textarea:not([disabled]):not([readonly]), input[type=\"text\"]:not([disabled]):not([readonly]), [contenteditable=\"true\"]'))
          ].filter((element, index, all) => element && all.indexOf(element) === index);
          const editor = candidates.find((element) => element.matches('textarea, input, [contenteditable=\"true\"]'));
          if (!editor) return false;
          editor.focus();
          if (editor.isContentEditable) {
            const selection = window.getSelection();
            if (selection && selection.rangeCount) {
              selection.getRangeAt(0).deleteContents();
              selection.getRangeAt(0).insertNode(document.createTextNode(inserted));
            } else {
              editor.append(document.createTextNode(inserted));
            }
          } else {
            const start = Number.isInteger(editor.selectionStart) ? editor.selectionStart : editor.value.length;
            const end = Number.isInteger(editor.selectionEnd) ? editor.selectionEnd : start;
            const value = editor.value || '';
            const nextValue = value.slice(0, start) + inserted + value.slice(end);
            const prototype = editor.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
            if (setter) setter.call(editor, nextValue); else editor.value = nextValue;
            const cursor = start + inserted.length;
            editor.setSelectionRange && editor.setSelectionRange(cursor, cursor);
          }
          editor.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: inserted }));
          editor.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        })();
        """
    }
}

extension PrivateMessageWebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "nodeSeekUploadImage" else { return }
        uploadImageTapped()
    }
}

extension PrivateMessageWebViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            showAlert(message: "请选择图片文件。")
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.showAlert(message: error.localizedDescription)
                    return
                }
                guard let data else {
                    self.showAlert(message: "读取图片失败。")
                    return
                }
                let typeIdentifier = provider.registeredTypeIdentifiers.first ?? UTType.jpeg.identifier
                let uniformType = UTType(typeIdentifier)
                let fileExtension = uniformType?.preferredFilenameExtension ?? "jpg"
                let mimeType = uniformType?.preferredMIMEType ?? "image/jpeg"
                self.uploadPickedImage(
                    data: data,
                    fileName: "nodeseek-message-\(Int(Date().timeIntervalSince1970)).\(fileExtension)",
                    mimeType: mimeType
                )
            }
        }
    }
}
