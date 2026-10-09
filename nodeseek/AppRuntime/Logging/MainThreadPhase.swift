//
//  MainThreadPhase.swift
//  nodeseek
//

import Foundation

/// 主线程"最后停在哪个动作上"的寄存器，用来回答卡死时主线程在干什么。
///
/// 之前两次卡死都只能靠手工在可疑位置加面包屑，覆盖面永远小于真凶所在。
/// 这里改成把 AppLog 每一条日志都当成一次面包屑：只有主线程写的日志会更新寄存器，
/// 所以看门狗报卡死时打印的那一行，就是主线程卡住之前最后一个**自己发过声**的动作。
/// 主线程完全不吭声的（同步排版、锁、XPC）看不到，那种情况靠"停留时长"和
/// 恢复日志来区分是慢还是死锁。
nonisolated final class MainThreadPhaseRecorder: @unchecked Sendable {
    static let shared = MainThreadPhaseRecorder()

    private static let messageLimit = 90

    private let lock = NSLock()
    private var phase = "（尚无主线程日志）"
    private var enteredAt = Date()

    private init() {}

    /// 非主线程调用直接忽略，否则寄存器会被后台任务污染。
    func record(_ message: String) {
        guard Thread.isMainThread else { return }
        let trimmed = message.count > Self.messageLimit ? String(message.prefix(Self.messageLimit)) : message
        lock.lock()
        phase = trimmed
        enteredAt = Date()
        lock.unlock()
    }

    /// `阶段文本（已停留 Nms）`
    var describe: String {
        lock.lock()
        let current = phase
        let since = Date().timeIntervalSince(enteredAt)
        lock.unlock()
        return "\(current)（已停留 \(Int(max(0, since) * 1000))ms）"
    }
}
