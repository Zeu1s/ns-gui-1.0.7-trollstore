//
//  SpaceMemberListAutomationScript.swift
//  nodeseek
//
//  Created by Codex on 2026/9/13.
//

import Foundation

/// 空间页/独立粉丝页的成员列表由登录态 SPA 渲染，SSR 不内嵌成员卡。
/// 在 WebView 加载的真实列表路由里轮询成员链接（/space/ 锚点），收集卡片信息。
/// 只认成员卡上下文里的链接，并剔除页主本人——此前全页收集把页头资料卡
/// 也当成员，导致列表为空、首项是页主（点进去像"跳到自己资料页"）。
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

      const isChrome = (anchor) => !!anchor.closest('header, nav, .header, .navbar, [class*="header"], [class*="nav"], footer');

      const collect = () => {
        const entries = [];
        const seen = new Set();
        const anchors = Array.from(document.querySelectorAll('a[href*="/space/"]'));
        for (const anchor of anchors) {
          if (isChrome(anchor)) continue;
          const href = anchor.getAttribute("href") || "";
          const match = href.match(/\\/space\\/(\\d+)/);
          if (!match) continue;
          const uid = parseInt(match[1], 10);
          if (!uid || seen.has(uid) || uid === ownerUid) continue;
          seen.add(uid);

          // 卡片取锚点自身或其直接父行：closest([class*='fans']) 会命中
          // 整个列表容器，导致每一行都取到容器里第一张头像与名字。
          const card = anchor.querySelector("img")
            ? anchor
            : (anchor.parentElement || anchor);
          let name = "";
          const img = card.querySelector("img");
          if (img) {
            name = (img.getAttribute("alt") || img.getAttribute("title") || "").trim();
          }
          if (!name) {
            name = (anchor.textContent || "").trim();
          }
          if (!name && card !== anchor) {
            const rowText = (card.textContent || "").trim();
            name = rowText.slice(0, 40);
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
