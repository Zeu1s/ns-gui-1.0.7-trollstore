//
//  SpaceReadmeAutomationScript.swift
//  nodeseek
//

import Foundation

/// 空间页 #/general 的 readme 由登录态 SPA 渲染，SSR 只有骨架。
/// 在 WebView 加载的空间页里轮询 readme 区块（class/id 含 readme），
/// 返回其 innerHTML 与纯文本；原生端按结构化 HTML 通道渲染。
enum SpaceReadmeAutomationScript {
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

      const find = () => {
        // 站点 readme 容器类名未公开：优先认 readme 命名，再放宽到
        // 概况面板里的 markdown 渲染容器，避免选择器失配拿不到内容。
        return document.querySelector('[class*="readme" i], [id*="readme" i]')
          || document.querySelector('.space-general [class*="markdown" i], [class*="introduction" i], [class*="intro" i]');
      };

      const collect = () => {
        const el = find();
        if (!el) return null;
        const text = (el.innerText || '').trim();
        if (!text) return null;
        return { ok: true, reason: 'ok', html: el.innerHTML, text };
      };

      try {
        timer = window.setTimeout(() => {
          const hit = collect();
          if (hit) { finish(hit); return; }
          // 超时自诊断：区分挑战页、容器缺失、内容为空三种情形。
          finish({
            ok: false,
            reason: 'timeout_empty',
            diagnose: {
              title: (document.title || '').slice(0, 60),
              bodyTextLength: (document.body.innerText || '').length,
              hasReadmeNode: !!document.querySelector('[class*="readme" i]'),
              isChallengePage: /just a moment|请稍候/i.test(document.title || '')
            }
          });
        }, timeoutMs);

        // SPA 异步渲染 readme：轮询直到出现或超时。
        let waited = 0;
        poll = window.setInterval(() => {
          waited += 400;
          const hit = collect();
          if (hit) {
            finish(hit);
            return;
          }
          if (waited >= timeoutMs) {
            finish({ ok: false, reason: 'timeout_empty' });
          }
        }, 400);
      } catch (error) {
        finish({
          ok: false,
          reason: 'network_error',
          message: String(error && error.message ? error.message : error)
        });
      }
    });
    """
}
