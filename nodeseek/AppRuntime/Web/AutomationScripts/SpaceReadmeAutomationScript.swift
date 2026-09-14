//
//  SpaceReadmeAutomationScript.swift
//  nodeseek
//

import Foundation

/// 空间页 readme 提取脚本。
/// 诊断发现：隐藏 WebView 里 SPA 渲染时容器 div.readme 存在但内容为空
/// （SPA 内部 API 请求未完成/失败）。因此脚本在页面上下文内直接
/// window.fetch 站点 API（同源、带 cf_clearance 与登录态）读取 readme，
/// 成功后回填到页面容器再提取 HTML，保证渲染管线拿到与网页一致的内容。
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
        return document.querySelector('div.readme, [class*="readme" i]')
          || document.querySelector('[class*="introduction" i], [class*="intro" i]');
      };

      const diagnose = () => ({
        title: (document.title || '').slice(0, 60),
        bodyTextLength: (document.body.innerText || '').length,
        hasReadmeNode: !!find(),
        isChallengePage: /just a moment|请稍候/i.test(document.title || '')
      });

      // uid 从当前路径 /space/{uid} 读取。
      const uidMatch = location.pathname.match(/\\/space\\/(\\d+)/);
      const uid = uidMatch ? uidMatch[1] : null;

      const fetchAPIReadme = async () => {
        if (!uid) return null;
        try {
          // 与站点 SPA 一致只带 readme=1；带 signature=1 服务端固定 500。
          const resp = await window.fetch('/api/account/getInfo/' + uid + '?readme=1', {
            method: 'GET',
            credentials: 'include',
            headers: { 'Accept': 'application/json' }
          });
          if (!resp.ok) return null;
          const json = await resp.json();
          const detail = json && json.detail;
          const readme = detail && typeof detail.readme === 'string' ? detail.readme : '';
          return readme.trim() ? readme : null;
        } catch (_) {
          return null;
        }
      };

      // markdown 转简易 HTML：链接/图片/换行，交给原生结构化 HTML 通道渲染。
      const markdownToHTML = (md) => {
        let html = md
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;');
        html = html.replace(new RegExp('!\\\\[\\\\]\\\\(([^)]+)\\\\)', 'g'), '<img src="$1" alt="">');
        html = html.replace(new RegExp('\\\\[([^\\\\]]+)\\\\]\\\\(([^)]+)\\\\)', 'g'), '<a href="$2">$1</a>');
        html = html.replace(new RegExp('\\\\*\\\\*([^*]+)\\\\*\\\\*', 'g'), '<strong>$1</strong>');
        html = html.split('\\n').join('<br>');
        return html;
      };

      const tryFetchAndFill = async () => {
        const apiReadme = await fetchAPIReadme();
        if (!apiReadme) return null;
        const el = find();
        if (el) {
          el.innerHTML = markdownToHTML(apiReadme);
        }
        return {
          ok: true,
          reason: 'api_fetch',
          html: markdownToHTML(apiReadme),
          text: apiReadme
        };
      };

      try {
        timer = window.setTimeout(async () => {
          const viaAPI = await tryFetchAndFill();
          if (viaAPI) { finish(viaAPI); return; }
          finish({ ok: false, reason: 'timeout_empty', diagnose: diagnose() });
        }, timeoutMs);

        let waited = 0;
        poll = window.setInterval(async () => {
          waited += 400;
          const el = find();
          if (el) {
            const text = (el.innerText || '').trim();
            if (text) {
              finish({ ok: true, reason: 'dom', html: el.innerHTML, text });
              return;
            }
          }
          // DOM 空时每 1.6 秒尝试一次 API 直读，最多触发 3 次后交给超时。
          if (waited >= 1600 && waited % 1600 === 0) {
            const viaAPI = await tryFetchAndFill();
            if (viaAPI) { finish(viaAPI); }
          }
          if (waited >= timeoutMs) {
            finish({ ok: false, reason: 'timeout_empty', diagnose: diagnose() });
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
