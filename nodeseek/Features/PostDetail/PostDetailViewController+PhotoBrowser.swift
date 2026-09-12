//
//  PostDetailViewController+PhotoBrowser.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit
import Photos

extension PostDetailViewController {
    func presentPhotoBrowser(imageURLs: [URL], initialIndex: Int) {
        guard imageURLs.isEmpty == false else { return }
        let presenter = DetailPhotoBrowserPresenter(imageURLs: imageURLs)
        photoBrowserPresenter = presenter
        presenter.present(from: self, initialIndex: initialIndex)
    }

    /// 正文图片长按菜单：查看大图 / 复制 / 保存。
    func presentImageActions(for imageURL: URL) {
        let resolvedURL = imageURL
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "查看大图", style: .default) { [weak self] _ in
            self?.presentPhotoBrowser(imageURLs: [resolvedURL], initialIndex: 0)
        })
        alert.addAction(UIAlertAction(title: "复制图片", style: .default) { _ in
            ImageLoad.url(resolvedURL).toOriginalPayload().load { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let payload):
                        if let photoData = DetailPhotoLibraryAssetData.data(from: payload) {
                            UIPasteboard.general.setData(photoData)
                            self.showToast(message: "已复制图片")
                            return
                        }
                        if let image = UIImage(data: payload.data) {
                            UIPasteboard.general.image = image
                            self.showToast(message: "已复制图片")
                        } else {
                            self.showToast(message: "图片转换失败")
                        }
                    case .failure:
                        self.showToast(message: "图片加载失败，暂时无法复制")
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: "保存到相册", style: .default) { _ in
            ImageLoad.url(resolvedURL).toOriginalPayload().load { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let payload):
                        guard let photoData = DetailPhotoLibraryAssetData.data(from: payload) else {
                            self.showToast(message: "图片转换失败")
                            return
                        }
                        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                            guard status == .authorized || status == .limited else {
                                DispatchQueue.main.async { self.showToast(message: "保存失败") }
                                return
                            }
                            PHPhotoLibrary.shared().performChanges {
                                let request = PHAssetCreationRequest.forAsset()
                                request.addResource(with: .photo, data: photoData, options: nil)
                            } completionHandler: { success, _ in
                                DispatchQueue.main.async {
                                    self.showToast(message: success ? "已保存到相册" : "保存失败")
                                }
                            }
                        }
                    case .failure:
                        DispatchQueue.main.async { self.showToast(message: "图片加载失败，暂时无法保存") }
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }
}
