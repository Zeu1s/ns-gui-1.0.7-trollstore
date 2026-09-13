//
//  SpaceMemberListAutomationScript.swift
//  nodeseek
//
//  Created by Codex on 2026/9/13.
//

import Foundation

/// 空间页粉丝/关注列表由登录态 SPA 渲染，SSR 不内嵌成员卡。
/// 在 WebView 加载的空间页里轮询成员链接（/space/ 锚点），收集卡片信息。
/// 输出与 FansListHTMLParser 兼容的字段：uid、name、avatar。
enum SpaceMemberListAutomationScript {
    static let source = """
    return await new Promise(async (resolve) => {
      let resolved = false;
      let timer = null;
      let poll = null;

      const finish = (payload) => {
        if (resolved) return;
        resolved = true;
        if (timer) window.clearTimeout(timer);
        if (poll) window.clearInterval(poll);
        resolve(payload);
      };

      const collect = () => {
        const entries = [];
        const seen = new Set();
        const anchors = Array.from(document.querySelectorAll('a[href*="/space/"]'));
        for (const anchor of anchors) {
          const href = anchor.getAttribute("href") || "";
          const match = href.match(/\\/space\\/(\\d+)/);
          if (!match) continue;
          const uid = parseInt(match[1], 10);
          if (!uid || seen.has(uid)) continue;
          seen.add(uid);

          const card = anchor.closest(".card-item, .member-item, [class*='member'], [class*='follow'], [class*='fans']") || anchor.parentElement || anchor;
          let name = "";
          const img = card.querySelector("img");
          if (img) {
            name = (img.getAttribute("alt") || img.getAttribute("title") || "").trim();
          }
          if (!name) {
            name = (anchor.textContent || "").trim();
          }
          if (!name) continue;
          const avatar = img ? (img.getAttribute("src") || img.getAttribute("data-src") || "") : "";
          entries.push({ uid, name, avatar });
        }
        return entries;
      };

      try {
        timer = window.setTimeout(() => {
          const entries = collect();
          finish({ ok: entries.length > 0, reason: entries.length > 0 ? "ok" : "timeout_empty", entries });
        }, timeoutMs);

        // SPA 异步渲染成员卡：轮询直到出现或超时。
        let waited = 0;
        poll = window.setInterval(() => {
          waited += 400;
          const entries = collect();
          if (entries.length > 0) {
            finish({ ok: true, reason: "ok", entries });
            return;
          }
          if (waited >= timeoutMs) {
            finish({ ok: false, reason: "timeout_empty", entries });
          }
        }, 400);
      } catch (error) {
        finish({
          ok: false,
          reason: "network_error",
          message: String(error && error.message ? error.message : error)
        });
      }
    });
    """
}
