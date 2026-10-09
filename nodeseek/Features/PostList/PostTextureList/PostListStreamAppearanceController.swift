//
//  PostListStreamAppearanceController.swift
//  nodeseek
//
//  Created by Codex on 2026/9/11.
//

import UIKit

/// 帖子列表的流式浮现动画控制器：登记即隐藏，按行序延迟逐条弹入。
/// pending 行、进行中的动画器等状态全部收在这里，宿主视图只转发时机。
final class PostListStreamAppearanceController {

    /// 调手感只改这一组参数。
    private enum Config {
        static let rowStaggerDelay: TimeInterval = 0.035
        static let duration: TimeInterval = 0.42
        static let springDamping: CGFloat = 0.86
        static let springVelocity: CGFloat = 0.4
        static let offsetY: CGFloat = 16
        static let initialScale: CGFloat = 0.98
        static let maximumInitialRowCount = 24
    }

    private weak var hostView: UIView?
    private weak var tableView: UITableView?

    private var pendingRowIndexes = Set<Int>()
    /// token → 动画器：计数天然精确，取消时也能逐个平滑收尾。
    private var activeAnimators: [Int: UIViewPropertyAnimator] = [:]
    private var nextAnimationToken = 0

    /// 还有等待播放的行或进行中的动画。
    var isBusy: Bool {
        pendingRowIndexes.isEmpty == false || activeAnimators.isEmpty == false
    }

    init(hostView: UIView, tableView: UITableView) {
        self.hostView = hostView
        self.tableView = tableView
    }

    /// 新数据即将 reloadData：登记首屏行，等待 willDisplay 逐行播放。
    func prepareInitialRows(count: Int) {
        stopAllAnimators()
        pendingRowIndexes = Set(0..<min(count, Config.maximumInitialRowCount))
    }

    /// 切换到骨架/错误页前取消流式，可见 cell 恢复默认外观。
    func cancelAndRestoreVisibleCells() {
        stopAllAnimators()
        pendingRowIndexes.removeAll()
        for cell in tableView?.visibleCells ?? [] {
            cell.layer.removeAllAnimations()
            cell.alpha = 1
            cell.transform = .identity
        }
    }

    /// 切回 tab 时重播：可见行整体隐下后逐条浮现；
    /// 没有可见行时退化为登记首屏行，等 willDisplay 补播。
    func replayVisibleRows(fallbackItemCount: Int) {
        guard let tableView, tableView.visibleCells.isEmpty == false else {
            prepareInitialRows(count: fallbackItemCount)
            return
        }
        let cells = tableView.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        for (index, cell) in cells.enumerated() {
            startStreamAnimation(cell, sequence: index)
        }
    }

    /// willDisplay 转发：pending 行开始流式播放，其余行只负责恢复被复用 cell 的残留初始态。
    func registerCellIfNeeded(_ cell: UIView, rowIndex: Int) {
        guard isHostReadyForAnimation else { return }
        registerVisibleCell(cell, rowIndex: rowIndex)
    }

    /// 布局时机转发（layoutSubviews / 重播前）：补播当前可见的 pending 行，
    /// 并在可见行盖满视口后放弃剩余 pending，避免下半屏等一个不会到来的动画。
    func layoutDidUpdate() {
        guard isBusy, isHostReadyForAnimation, let tableView else { return }
        for cell in tableView.visibleCells.sorted(by: { $0.frame.minY < $1.frame.minY }) {
            guard let row = tableView.indexPath(for: cell)?.row else { continue }
            registerVisibleCell(cell, rowIndex: row)
        }
        finalizeIfViewportCovered()
    }

    // MARK: - Private

    private func registerVisibleCell(_ cell: UIView, rowIndex: Int) {
        if pendingRowIndexes.remove(rowIndex) != nil {
            startStreamAnimation(cell, sequence: rowIndex)
            finalizeIfViewportCovered()
        } else if cell.alpha != 1 || cell.transform != .identity {
            // 复用的 cell 可能残留流式初始态（透明+位移），进屏前恢复默认外观。
            cell.layer.removeAllAnimations()
            cell.alpha = 1
            cell.transform = .identity
        }
    }

    private func startStreamAnimation(_ cell: UIView, sequence: Int) {
        cell.layer.removeAllAnimations()
        cell.alpha = 0
        cell.transform = CGAffineTransform(translationX: 0, y: Config.offsetY)
            .scaledBy(x: Config.initialScale, y: Config.initialScale)

        let animator = UIViewPropertyAnimator(
            duration: Config.duration,
            timingParameters: UISpringTimingParameters(
                dampingRatio: Config.springDamping,
                initialVelocity: CGVector(dx: 0, dy: Config.springVelocity)
            )
        )
        animator.addAnimations { [weak cell] in
            cell?.alpha = 1
            cell?.transform = .identity
        }
        let token = nextAnimationToken
        nextAnimationToken += 1
        animator.addCompletion { [weak self] _ in
            self?.activeAnimators.removeValue(forKey: token)
        }
        activeAnimators[token] = animator
        animator.startAnimation(afterDelay: Double(sequence) * Config.rowStaggerDelay)
    }

    /// Texture 可能在首行显示后才提交底部行。等真实可见行覆盖到视口底部再结束首屏流式，
    /// 避免固定延时让下半屏错过动画。
    private func finalizeIfViewportCovered() {
        guard pendingRowIndexes.isEmpty == false,
              let tableView
        else {
            return
        }

        let visibleBottom = tableView.bounds.maxY - tableView.adjustedContentInset.bottom
        guard visibleBottom > tableView.bounds.minY else { return }

        let lastVisibleCellBottom = tableView.visibleCells.map(\.frame.maxY).max() ?? 0
        let contentEndsInsideViewport = tableView.contentSize.height
            <= visibleBottom + tableView.adjustedContentInset.bottom + 1
        guard contentEndsInsideViewport || lastVisibleCellBottom >= visibleBottom - 1 else {
            return
        }
        pendingRowIndexes.removeAll()
    }

    /// 宿主自身和全部祖先视图都可见时才播放，数据在被遮挡页到达时也不会丢动画。
    private var isHostReadyForAnimation: Bool {
        guard let hostView, hostView.window != nil else { return false }
        var candidate: UIView? = hostView
        while let view = candidate {
            guard view.isHidden == false, view.alpha > 0.01 else { return false }
            candidate = view.superview
        }
        return true
    }

    /// stop 之后必须 finish 才能释放；已自然结束的动画器停在 inactive，按状态跳过。
    private func stopAllAnimators() {
        let animators = Array(activeAnimators.values)
        activeAnimators.removeAll()
        for animator in animators {
            animator.stopAnimation(true)
            if animator.state == .stopped {
                animator.finishAnimation(at: .current)
            }
        }
    }
}
