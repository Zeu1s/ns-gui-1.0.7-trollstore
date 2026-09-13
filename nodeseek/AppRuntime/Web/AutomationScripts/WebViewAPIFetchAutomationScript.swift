//
//  WebViewAPIFetchAutomationScript.swift
//  nodeseek
//
//  Created by Codex on 2026/9/13.
//

import Foundation

/// 在已通过 Cloudflare 的宿主页面上下文里，用同源 window.fetch 请求站点 API。
/// 用于绕过 URLSession 请求特征被 Cloudflare 指纹封锁的场景：
/// WebView 内 fetch 是完整浏览器网络栈，携带页面已通过的 cf_clearance 与完整指纹，
/// 不会被当作无头客户端拦截。
enum WebViewAPIFetchAutomationScript {
    static let source = """
    return await new Promise(async (resolve) => {
      let resolved = false;
      let timer = null;

      const finish = (payload) => {
        if (resolved) return;
        resolved = true;
        if (timer) window.clearTimeout(timer);
        resolve(payload);
      };

      try {
        timer = window.setTimeout(() => {
          finish({ ok: false, reason: "fetch_timeout" });
        }, timeoutMs);

        const init = {
          method: method,
          credentials: "include",
          headers: {}
        };
        if (headers && typeof headers === "object") {
          for (const key of Object.keys(headers)) {
            init.headers[key] = headers[key];
          }
        }
        if (body !== null && body !== undefined && body !== "") {
          init.body = body;
          if (!init.headers["Content-Type"]) {
            init.headers["Content-Type"] = "application/json";
          }
        }

        const response = await window.fetch(apiPath, init);
        const text = await response.text();
        const json = (() => {
          try {
            return JSON.parse(text || "{}");
          } catch (_) {
            return {};
          }
        })();

        finish({
          ok: response.status >= 200 && response.status < 300,
          statusCode: response.status,
          body: text,
          json: json,
          reason: response.status >= 200 && response.status < 300 ? "ok" : "http_error"
        });
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
