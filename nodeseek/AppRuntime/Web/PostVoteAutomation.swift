//
//  PostVoteAutomation.swift
//  nodeseek
//

import Foundation

struct PostVoteSubmissionResponse: Equatable, Sendable {
    let vote: PostVote
    let message: String?
}

protocol PostVoteSubmitting: AnyObject {
    func loadVote(referer: URL) async throws -> PostVote?
    func submitVote(optionIDs: [String], referer: URL) async throws -> PostVoteSubmissionResponse
}

private struct PostVoteAutomationResponse: PostActionAutomationResult {
    let ok: Bool
    let reason: String
    let message: String?
    let vote: PostVote?

    init(payload: [String: Any]) {
        ok = payload["ok"] as? Bool ?? false
        reason = payload["reason"] as? String ?? "unknown"
        message = payload["message"] as? String
        vote = Self.vote(from: payload["vote"] as? [String: Any])
    }

    private static func vote(from dictionary: [String: Any]?) -> PostVote? {
        guard let dictionary,
              let rawOptions = dictionary["options"] as? [[String: Any]] else {
            return nil
        }
        let options = rawOptions.compactMap { raw -> PostVoteOption? in
            guard let id = raw["id"] as? String,
                  id.isEmpty == false,
                  let title = raw["title"] as? String,
                  title.isEmpty == false else {
                return nil
            }
            return PostVoteOption(
                id: id,
                title: title,
                voteCount: raw["voteCount"] as? Int,
                isSelected: raw["isSelected"] as? Bool ?? false
            )
        }
        guard options.isEmpty == false else { return nil }
        return PostVote(
            id: dictionary["id"] as? String,
            title: (dictionary["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "投票",
            allowsMultipleSelection: dictionary["allowsMultipleSelection"] as? Bool ?? false,
            totalVoteCount: dictionary["totalVoteCount"] as? Int,
            statusText: (dictionary["statusText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            isClosed: dictionary["isClosed"] as? Bool ?? false,
            canSubmit: dictionary["canSubmit"] as? Bool ?? false,
            options: options
        )
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private final class WebViewPostVoteAutomator {
    private let client: HiddenWebViewPostVoteClient

    init(client: HiddenWebViewPostVoteClient = HiddenWebViewPostVoteClient()) {
        self.client = client
    }

    func loadVote(referer: URL) async throws -> PostVote? {
        try await client.loadVote(referer: referer).vote
    }

    func submitVote(optionIDs: [String], referer: URL) async throws -> PostVoteAutomationResponse {
        try await client.submitVote(optionIDs: optionIDs, referer: referer)
    }
}

final class NodeSeekPostVoteSubmitter: PostVoteSubmitting {
    private let automator: WebViewPostVoteAutomator

    init() {
        automator = WebViewPostVoteAutomator()
    }

    private init(automator: WebViewPostVoteAutomator) {
        self.automator = automator
    }

    func loadVote(referer: URL) async throws -> PostVote? {
        try await automator.loadVote(referer: referer)
    }

    func submitVote(optionIDs: [String], referer: URL) async throws -> PostVoteSubmissionResponse {
        let normalizedOptionIDs = Array(
            Set(optionIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        ).filter { $0.isEmpty == false }
        guard normalizedOptionIDs.isEmpty == false else {
            throw NodeSeekPostVoteSubmitterError.noSelection
        }

        let response = try await automator.submitVote(optionIDs: normalizedOptionIDs, referer: referer)
        guard response.ok else {
            throw NodeSeekPostVoteSubmitterError.serverMessage(
                response.message?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? "投票提交失败，请稍后重试。"
            )
        }
        guard let vote = response.vote else {
            throw NodeSeekPostVoteSubmitterError.invalidResponse
        }
        return PostVoteSubmissionResponse(vote: vote, message: response.message)
    }
}

enum NodeSeekPostVoteSubmitterError: LocalizedError, Equatable {
    case noSelection
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "请先选择投票选项。"
        case .invalidResponse:
            return "投票提交后未获取到最新结果，请刷新帖子后重试。"
        case .serverMessage(let message):
            return message
        }
    }
}

private struct HiddenWebViewPostVoteClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func loadVote(referer: URL) async throws -> PostVoteAutomationResponse {
        try await withPostActionHiddenWebViewLoader(
            logMessage: "准备读取帖子投票状态: referer=\(referer.absoluteString)"
        ) { loader in
            let payload = try await loader.runPageAutomationScript(
                pageURL: referer,
                source: PostVoteAutomationScript.source,
                arguments: ["mode": "snapshot", "optionIDs": []],
                timeoutInterval: timeoutInterval,
                actionName: "读取投票状态"
            )
            return PostVoteAutomationResponse(payload: payload)
        }
    }

    func submitVote(optionIDs: [String], referer: URL) async throws -> PostVoteAutomationResponse {
        let submitter = HiddenWebViewPostActionSubmitter(timeoutInterval: timeoutInterval)
        return try await submitter.submit(
            referer: referer,
            actionName: "投票提交",
            logMessage: "准备提交帖子投票: optionCount=\(optionIDs.count), referer=\(referer.absoluteString)"
        ) { loader in
            let payload = try await loader.runPageAutomationScript(
                pageURL: referer,
                source: PostVoteAutomationScript.source,
                arguments: ["mode": "submit", "optionIDs": optionIDs],
                timeoutInterval: timeoutInterval,
                actionName: "投票提交"
            )
            return PostVoteAutomationResponse(payload: payload)
        }
    }
}

private enum PostVoteAutomationScript {
    static let source = """
    return await new Promise(async (resolve) => {
      const sleep = (milliseconds) => new Promise((done) => window.setTimeout(done, milliseconds));
      const compact = (value) => String(value || "").replace(/\\s+/g, " ").trim();
      const numberIn = (value) => {
        const matched = compact(value).match(/\\d+/);
        return matched ? Number(matched[0]) : null;
      };
      const voteRoot = () => document.querySelector("#vote-editor-mount");
      const hasVote = (root) => root && (root.querySelectorAll("input, [role='radio'], [role='checkbox']").length > 0 || /投票|单选|多选/.test(compact(root.textContent)));
      const waitForVote = async () => {
        // 只读快照不能把全局 WebView 锁占满整个超时：绝大多数帖子根本没有投票，
        // 等满 20 秒只会让后面每个帖子排队（真机日志实测锁占用 21.5 秒）。
        // 投票挂载点在 didFinish 之后由页面脚本创建，3 秒足够；
        // 用户主动提交的场景仍用完整超时。
        const budget = mode === "submit" ? timeoutMs : Math.min(timeoutMs, 3000);
        const deadline = Date.now() + budget;
        while (Date.now() < deadline) {
          const root = voteRoot();
          if (hasVote(root)) return root;
          await sleep(120);
        }
        return hasVote(voteRoot()) ? voteRoot() : null;
      };
      const optionID = (node, index) => {
        const values = [
          node.getAttribute("value"), node.getAttribute("data-option-id"), node.getAttribute("data-vote-option-id"),
          node.getAttribute("data-id"), node.id, node.getAttribute("aria-controls")
        ];
        const value = values.map(compact).find((item) => item.length > 0);
        return value || `index-${index}`;
      };
      const optionHost = (node) => node.closest("label, .vote-option, .vote-item, .option, [role='radio'], [role='checkbox']") || node.parentElement || node;
      const selected = (node, host) => node.checked === true || node.getAttribute("aria-checked") === "true" || /selected|active|checked|clicked/.test(`${node.className || ""} ${host.className || ""}`.toLowerCase());
      const readCount = (host) => {
        const attrs = ["data-vote-count", "data-count", "data-votes", "data-total"];
        for (const name of attrs) {
          const value = numberIn(host.getAttribute(name));
          if (value !== null) return value;
        }
        const text = compact(host.textContent);
        const matched = text.match(/(\\d+)\\s*(?:票|votes?)/i);
        return matched ? Number(matched[1]) : null;
      };
      const controls = (root) => Array.from(root.querySelectorAll("input[type='radio'], input[type='checkbox'], [role='radio'], [role='checkbox']"));
      const submitButton = (root) => Array.from(root.querySelectorAll("button, input[type='submit'], [role='button']")).find((node) => /投票|提交/.test(compact(node.getAttribute("title") || node.value || node.textContent))) || null;
      const snapshot = (root) => {
        const nodes = controls(root);
        const options = nodes.map((node, index) => {
          const host = optionHost(node);
          const text = compact(host.textContent) || compact(node.getAttribute("aria-label")) || `选项 ${index + 1}`;
          return { id: optionID(node, index), title: text, voteCount: readCount(host), isSelected: selected(node, host) };
        });
        const text = compact(root.textContent);
        const heading = root.querySelector(".vote-title, .vote-question, h1, h2, h3, h4, strong, b");
        const totalMatch = text.match(/(?:共|已有)?\\s*(\\d+)\\s*(?:人参与|票|votes?)/i);
        const closed = /投票(?:已)?结束|投票已截止|已关闭/.test(text);
        const button = submitButton(root);
        const status = text.match(/(?:投票(?:已)?结束|已截止|已投票|共\\s*\\d+\\s*(?:人参与|票))/)?.[0] || null;
        return {
          id: compact(root.getAttribute("data-vote-id") || root.getAttribute("data-id")) || null,
          title: compact(heading?.textContent) || "投票",
          allowsMultipleSelection: nodes.some((node) => String(node.getAttribute("type") || "").toLowerCase() === "checkbox") || /多选/.test(text),
          totalVoteCount: totalMatch ? Number(totalMatch[1]) : null,
          statusText: status,
          isClosed: closed,
          canSubmit: Boolean(button && !button.disabled && !closed),
          options
        };
      };

      const root = await waitForVote();
      if (!root) {
        resolve({ ok: false, reason: "vote_not_found", message: null });
        return;
      }

      if (mode === "submit") {
        const wanted = new Set((Array.isArray(optionIDs) ? optionIDs : []).map((item) => String(item)));
        const nodes = controls(root);
        for (let index = 0; index < nodes.length; index += 1) {
          const node = nodes[index];
          if (!wanted.has(optionID(node, index))) continue;
          const host = optionHost(node);
          if (selected(node, host)) continue;
          if (typeof node.click === "function") node.click();
          else if (typeof host.click === "function") host.click();
        }
        const button = submitButton(root);
        if (!button || button.disabled) {
          resolve({ ok: false, reason: "vote_submit_unavailable", message: "当前投票不可提交", vote: snapshot(root) });
          return;
        }
        button.click();
        await sleep(700);
        const errorText = compact(root.textContent).match(/投票失败|请先(?:选择|登录)|无权投票|操作失败/)?.[0] || null;
        resolve({ ok: !errorText, reason: errorText ? "server_error" : "submitted", message: errorText, vote: snapshot(root) });
        return;
      }

      resolve({ ok: true, reason: "snapshot", message: null, vote: snapshot(root) });
    });
    """
}
