//
//  DetailImageLayout.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import CoreGraphics

nonisolated enum DetailImageDisplayMode: Equatable, Sendable {
    case thumbnailCrop
    case aspectFit
}

nonisolated enum DetailImageKind: Equatable, Sendable {
    case normal
    case sticker
    case report
}

nonisolated struct DetailImagePresentation: Equatable, Sendable {
    let size: CGSize
    let mode: DetailImageDisplayMode

    var targetPointSide: CGFloat {
        max(size.width, size.height)
    }
}

nonisolated enum DetailImageLayout {
    static let fixedStickerHeight: CGFloat = 65
    static let maxImageHeight: CGFloat = 420
    private static let extremeAspectRatio: CGFloat = 1.8
    private static let reportPlaceholderAspectRatio: CGFloat = 16 / 9

    static func fixedNormalImageSize(maxWidth: CGFloat) -> CGSize {
        guard maxWidth > 0 else { return .zero }
        let side = max(1, floor(maxWidth / 2))
        return CGSize(width: side, height: side)
    }

    static func reportPlaceholderSize(maxWidth: CGFloat) -> CGSize {
        guard maxWidth > 0 else { return .zero }
        return CGSize(width: maxWidth, height: ceil(maxWidth / reportPlaceholderAspectRatio))
    }

    static func scaledSize(
        for size: CGSize,
        maxWidth: CGFloat,
        maxHeight: CGFloat?
    ) -> CGSize {
        guard size.width > 0, size.height > 0, maxWidth > 0 else { return size }

        var scale = min(1, maxWidth / size.width)
        if let maxHeight, maxHeight > 0 {
            scale = min(scale, maxHeight / size.height)
        }

        return CGSize(
            width: max(1, size.width * scale),
            height: max(1, size.height * scale)
        )
    }

    static func placeholderSize(
        maxWidth: CGFloat,
        kind: DetailImageKind
    ) -> CGSize {
        guard maxWidth > 0 else { return .zero }

        if kind == .sticker {
            return CGSize(
                width: max(1, min(maxWidth, fixedStickerHeight)),
                height: fixedStickerHeight
            )
        }

        if kind == .report {
            return reportPlaceholderSize(maxWidth: maxWidth)
        }

        return fixedNormalImageSize(maxWidth: maxWidth)
    }

    static func presentation(
        for originalSize: CGSize,
        maxWidth: CGFloat,
        kind: DetailImageKind
    ) -> DetailImagePresentation {
        guard maxWidth > 0 else {
            return DetailImagePresentation(size: .zero, mode: .aspectFit)
        }

        switch kind {
        case .sticker:
            return stickerPresentation(for: originalSize, maxWidth: maxWidth)
        case .normal:
            return normalPresentation(for: originalSize, maxWidth: maxWidth)
        case .report:
            return reportPresentation(for: originalSize, maxWidth: maxWidth)
        }
    }

    private static func stickerPresentation(for originalSize: CGSize, maxWidth: CGFloat) -> DetailImagePresentation {
        let size: CGSize
        if originalSize.width > 0, originalSize.height > 0 {
            let scaledWidth = originalSize.width * fixedStickerHeight / originalSize.height
            size = CGSize(
                width: max(1, min(maxWidth, scaledWidth)),
                height: fixedStickerHeight
            )
        } else {
            size = placeholderSize(maxWidth: maxWidth, kind: .sticker)
        }
        return DetailImagePresentation(size: size, mode: .aspectFit)
    }

    private static func normalPresentation(for originalSize: CGSize, maxWidth: CGFloat) -> DetailImagePresentation {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return DetailImagePresentation(size: fixedNormalImageSize(maxWidth: maxWidth), mode: .thumbnailCrop)
        }

        // 帖子图片一律按比例完整显示，不再裁剪半屏等待手动点开。
        return DetailImagePresentation(
            size: scaledSize(for: originalSize, maxWidth: maxWidth, maxHeight: nil),
            mode: .aspectFit
        )
    }

    private static func reportPresentation(for originalSize: CGSize, maxWidth: CGFloat) -> DetailImagePresentation {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return DetailImagePresentation(size: reportPlaceholderSize(maxWidth: maxWidth), mode: .aspectFit)
        }
        return DetailImagePresentation(
            size: scaledSize(for: originalSize, maxWidth: maxWidth, maxHeight: nil),
            mode: .aspectFit
        )
    }

    static func allowsInlineAnimation(
        for originalSize: CGSize,
        maxWidth: CGFloat,
        kind: DetailImageKind
    ) -> Bool {
        if kind == .sticker {
            return true
        }

        guard originalSize.width > 0, originalSize.height > 0 else { return false }
        return originalSize.width / originalSize.height > 1 / extremeAspectRatio
    }
}
