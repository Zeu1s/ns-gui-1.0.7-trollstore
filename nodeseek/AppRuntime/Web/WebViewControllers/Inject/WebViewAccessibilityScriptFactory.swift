//
//  WebViewAccessibilityScriptFactory.swift
//  nodeseek
//

import Foundation
import WebKit

enum WebViewAccessibilityScriptFactory {
    static func makeDisplayScaleScript(
        scale: CGFloat = AppDisplayScaleSettings.shared.scale
    ) -> WKUserScript {
        WKUserScript(
            source: displayScaleJavaScript(scale: scale),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    static func updateDisplayScaleJavaScript(
        scale: CGFloat = AppDisplayScaleSettings.shared.scale
    ) -> String {
        "window.__nodeSeekApplyDisplayScale && window.__nodeSeekApplyDisplayScale(\(normalizedScaleLiteral(scale)));"
    }

    private static func displayScaleJavaScript(scale: CGFloat) -> String {
        """
        (() => {
          const host = window.location.hostname.toLowerCase();
          if (host !== 'nodeseek.com' && !host.endsWith('.nodeseek.com')) return;

          const styleID = 'nodeseek-display-scale-style';
          const pageRoute = () => `${window.location.pathname}${window.location.hash}`.toLowerCase();
          const applyMobilePageClasses = () => {
            const root = document.documentElement;
            if (!root) return;
            const route = pageRoute();
            const isPrivateMessagePage = route.includes('/message');
            const isProfilePage = route.includes('/space/');
            root.classList.toggle('nodeseek-private-message-page', isPrivateMessagePage);
            root.classList.toggle('nodeseek-profile-page', isProfilePage);

            if (!isProfilePage) return;
            document.querySelectorAll('[class*="medal"], [class*="badge"], img[alt*="勋章"], img[title*="勋章"]').forEach((element) => {
              const label = `${element.getAttribute('alt') || ''} ${element.getAttribute('title') || ''} ${element.textContent || ''}`;
              const className = String(element.getAttribute('class') || '').toLowerCase();
              if (label.includes('勋章') || className.includes('medal')) {
                element.classList.add('nodeseek-profile-medal');
                element.parentElement?.classList.add('nodeseek-profile-medal-list');
              }
            });
            const profileStatLabels = ['加入天数', '等级', 'Lv', '鸡腿数目', '主题帖数', '评论数'];
            const statCards = [];
            document.querySelectorAll('[class*="stat"], [class*="data"], [class*="info"], [class*="card"]').forEach((element) => {
              const label = (element.textContent || '').replace(/\\s+/g, '');
              if (profileStatLabels.some((item) => label.includes(item)) && label.length <= 96) {
                element.classList.add('nodeseek-profile-stat-card');
                statCards.push(element);
              }
              if (label.includes('加入天数') || label.includes('等级') || label.includes('Lv')) {
                element.classList.add('nodeseek-profile-priority-stat');
              }
            });
            statCards.forEach((card) => {
              const parent = card.parentElement;
              if (!parent) return;
              const directCards = Array.from(parent.children).filter((child) => child.classList.contains('nodeseek-profile-stat-card'));
              if (directCards.length >= 2) parent.classList.add('nodeseek-profile-stats-grid');
            });
          };
          const userBadgeState = {};
          const userBadgeStyleID = 'nodeseek-user-badge-style';
          const ensureUserBadgeStyle = () => {
            let style = document.getElementById(userBadgeStyleID);
            if (!style) {
              style = document.createElement('style');
              style.id = userBadgeStyleID;
              (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = `
              .nodeseek-user-info-badge{display:inline-flex;align-items:center;margin-left:6px;padding:2px 7px;border-radius:999px;background:linear-gradient(135deg,#22c55e,#16a34a);color:#fff!important;font-size:11px;font-weight:600;line-height:16px;vertical-align:middle;white-space:nowrap;text-decoration:none!important;pointer-events:none}
              .info-author .nodeseek-user-info-badge{margin-left:4px}
            `;
          };
          const appendUserBadge = (anchor, text) => {
            if (!text) return;
            const container = anchor.closest('.author-info') || anchor.parentElement;
            if (!container) return;
            if (container.querySelector(':scope > .nodeseek-user-info-badge')) return;
            const badge = document.createElement('span');
            badge.className = 'nodeseek-user-info-badge';
            badge.textContent = text;
            container.appendChild(badge);
          };
          const fetchUserBadge = (userId, anchor) => {
            if (userBadgeState[userId]) {
              appendUserBadge(anchor, userBadgeState[userId]);
              return;
            }
            fetch('/api/account/getInfo/' + userId, { credentials: 'include' })
              .then((response) => response.ok ? response.json() : null)
              .then((payload) => {
                const detail = payload && payload.success ? payload.detail : null;
                if (!detail) return;
                const createdAt = detail.created_at ? new Date(detail.created_at).getTime() : NaN;
                const joinDays = Number.isFinite(createdAt) ? Math.max(1, Math.ceil((Date.now() - createdAt) / 86400000)) : 0;
                const coin = Number(detail.coin) || 0;
                const level = Number(detail.rank) || Math.min(6, Math.floor(Math.sqrt(coin) / 10));
                const badgeText = 'Lv ' + level + (joinDays > 0 ? ' · ' + joinDays + '天' : '');
                userBadgeState[userId] = badgeText;
                appendUserBadge(anchor, badgeText);
              })
              .catch(() => {});
          };
          const applyUserInfoBadges = () => {
            ensureUserBadgeStyle();
            const anchors = Array.from(document.querySelectorAll('a.author-name[href*="/space/"], .info-author a[href*="/space/"]'))
              .filter((anchor) => !anchor.dataset.nodeseekUserInfoHandled);
            anchors.forEach((anchor) => {
              anchor.dataset.nodeseekUserInfoHandled = '1';
              const match = (anchor.getAttribute('href') || '').match(/\\/space\\/(\\d+)/);
              if (!match) return;
              fetchUserBadge(match[1], anchor);
            });
            Array.from(document.querySelectorAll('.post-list-item')).forEach((item) => {
              const authorLink = item.querySelector('.info-author a, .post-author a');
              if (!authorLink || authorLink.dataset.nodeseekUserInfoHandled) return;
              const href = authorLink.getAttribute('href') || '';
              if (href.includes('/space/')) return;
              const avatar = item.querySelector('img[data-uid]');
              const userId = avatar && avatar.getAttribute('data-uid');
              if (!userId) return;
              authorLink.dataset.nodeseekUserInfoHandled = '1';
              fetchUserBadge(userId, authorLink);
            });
          };          let mobilePageRefreshScheduled = false;
          const scheduleMobilePageRefresh = () => {
            if (mobilePageRefreshScheduled) return;
            mobilePageRefreshScheduled = true;
            requestAnimationFrame(() => {
              mobilePageRefreshScheduled = false;
              applyMobilePageClasses();
              applyUserInfoBadges();
            });
          };
          const ensureViewport = () => {
            let viewport = document.querySelector('meta[name="viewport"]');
            if (!viewport) {
              viewport = document.createElement('meta');
              viewport.name = 'viewport';
              document.head && document.head.appendChild(viewport);
            }
            if (viewport) {
              viewport.setAttribute(
                'content',
                'width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover'
              );
            }
          };
          const apply = (rawScale) => {
            const scale = Math.min(1.2, Math.max(0.7, Number(rawScale) || 1));
            const inputFontSize = Math.max(16, 16 * scale);
            const messageFontSize = 17;
            const root = document.documentElement;
            if (!root) return;
            root.style.setProperty('--nodeseek-display-scale', String(scale));
            applyMobilePageClasses();
            let style = document.getElementById(styleID);
            if (!style) {
              style = document.createElement('style');
              style.id = styleID;
              (document.head || root).appendChild(style);
            }
            // CSS zoom 让网页中的间距、图片和控件与文字一起缩放；输入框仍保持 16px，避免 iOS 聚焦时自动放大页面。
            style.textContent = `
              html {
                width: 100% !important;
                overflow-x: hidden !important;
              }
              body {
                zoom: var(--nodeseek-display-scale) !important;
                width: calc(100% / var(--nodeseek-display-scale)) !important;
                min-height: calc(100% / var(--nodeseek-display-scale)) !important;
                transform: none !important;
                transform-origin: initial !important;
                overflow-x: hidden !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page #nsk-head,
              html.nodeseek-profile-page #nsk-head,
              html.nodeseek-private-message-page body > header,
              html.nodeseek-profile-page body > header {
                display: none !important;
              }
              html.nodeseek-private-message-page :is(#app, #nsk-body, #nsk-body-left, #nsk-body-right, [class*="notification"], [class*="message"], [class*="conversation"], [class*="editor"]),
              html.nodeseek-profile-page :is(#app, #nsk-body, #nsk-body-left, #nsk-body-right, [class*="profile"], [class*="user-info"], [class*="user-card"]) {
                width: 100% !important;
                max-width: 100% !important;
                min-width: 0 !important;
                margin-left: 0 !important;
                margin-right: 0 !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page :is(main, section, form, [class*="content"], [class*="body"], [class*="panel"]),
              html.nodeseek-profile-page :is(main, section, [class*="content"], [class*="body"], [class*="panel"]) {
                min-width: 0 !important;
                max-width: 100% !important;
                overflow-x: hidden !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page :is(#nsk-body, [class*="message"], [class*="conversation"], [class*="editor"], [class*="toolbar"], [class*="action"]),
              html.nodeseek-profile-page :is([class*="profile"], [class*="user-info"], [class*="user-card"]) {
                min-width: 0 !important;
                max-width: 100% !important;
              }
              html.nodeseek-private-message-page [style*="width"],
              html.nodeseek-profile-page [style*="width"] {
                max-width: 100% !important;
              }
              html.nodeseek-private-message-page body,
              html.nodeseek-private-message-page #app,
              html.nodeseek-private-message-page #nsk-body {
                background: #f6f7f9 !important;
                color: #20242b !important;
              }
              html.nodeseek-private-message-page :is(textarea, input[type="text"], [contenteditable="true"]) {
                width: 100% !important;
                max-width: 100% !important;
                height: 132px !important;
                min-height: 112px !important;
                max-height: 160px !important;
                padding: 12px !important;
                background: #ffffff !important;
                color: #20242b !important;
                border: 1px solid #d7dbe2 !important;
                border-radius: 8px !important;
              }
              html.nodeseek-private-message-page :is(form, [class*="toolbar"], [class*="action"], [class*="footer"], [class*="editor"]) {
                display: flex !important;
                flex-wrap: wrap !important;
                gap: 8px !important;
                width: 100% !important;
                min-width: 0 !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page :is(form, [class*="toolbar"], [class*="action"], [class*="footer"], [class*="editor"]) > * {
                min-width: 0 !important;
                max-width: 100% !important;
              }
              html.nodeseek-private-message-page :is(button, a[role="button"]) {
                max-width: 100% !important;
                min-width: 0 !important;
                white-space: normal !important;
              }
              html.nodeseek-private-message-page [class*="message"] :is(article, .content, [class*="content"], [class*="bubble"]),
              html.nodeseek-private-message-page [class*="conversation"] :is(article, .content, [class*="content"], [class*="bubble"]) {
                background: #ffffff !important;
                border-color: #dfe3e8 !important;
                color: #20242b !important;
              }
              html.nodeseek-profile-page body,
              html.nodeseek-profile-page #app,
              html.nodeseek-profile-page #nsk-body {
                background: #f6f7f9 !important;
                color: #20242b !important;
              }
              html.nodeseek-profile-page .nodeseek-profile-stats-grid {
                display: grid !important;
                grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
                gap: 8px !important;
                width: 100% !important;
                overflow: visible !important;
              }
              html.nodeseek-profile-page .nodeseek-profile-stat-card {
                width: auto !important;
                min-width: 0 !important;
                max-width: 100% !important;
                margin: 0 !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-profile-page .nodeseek-profile-priority-stat {
                order: -1 !important;
              }
              html.nodeseek-profile-page .nodeseek-profile-medal-list {
                display: flex !important;
                flex-wrap: wrap !important;
                align-items: center !important;
                gap: 4px !important;
                max-width: 100% !important;
              }
              html.nodeseek-profile-page .nodeseek-profile-medal {
                display: inline-flex !important;
                align-items: center !important;
                gap: 4px !important;
                min-height: 28px !important;
                padding: 4px 8px !important;
                margin: 2px !important;
                border: 1px solid #e2b55b !important;
                border-radius: 6px !important;
                background: #fff8e9 !important;
                color: #8a5a10 !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page #nsk-left-panel-container,
              html.nodeseek-profile-page #nsk-left-panel-container,
              html.nodeseek-profile-page #nsk-right-panel-container,
              html.nodeseek-profile-page #nsk-body-right {
                display: none !important;
              }
              html.nodeseek-private-message-page #nsk-frame,
              html.nodeseek-profile-page #nsk-frame {
                width: 100% !important;
                max-width: 100% !important;
                min-width: 0 !important;
              }
              html.nodeseek-private-message-page #nsk-body,
              html.nodeseek-profile-page #nsk-body {
                display: block !important;
                width: 100% !important;
                max-width: 100% !important;
                min-width: 0 !important;
                margin: 0 !important;
                padding: 0 !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page #nsk-body-left,
              html.nodeseek-private-message-page #nsk-body-right,
              html.nodeseek-profile-page #nsk-body-left {
                display: block !important;
                float: none !important;
                width: 100% !important;
                max-width: 100% !important;
                min-width: 0 !important;
                margin: 0 !important;
                padding: 0 4px 24px !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page .nsk-container,
              html.nodeseek-profile-page .nsk-container {
                width: 100% !important;
                max-width: 100% !important;
                min-width: 0 !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page #nsk-body-left :is(div, section, article, form, table, ul, li, .content-item, [class*="panel"], [class*="card"]),
              html.nodeseek-profile-page #nsk-body-left :is(div, section, article, form, table, ul, li, .content-item, [class*="panel"], [class*="card"]) {
                max-width: 100% !important;
                min-width: 0 !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page #nsk-body-left img,
              html.nodeseek-profile-page #nsk-body-left img {
                max-width: 100% !important;
                height: auto !important;
              }              html.nodeseek-private-message-page,
              html.nodeseek-profile-page {
                overflow-x: hidden !important;
                max-width: 100vw !important;
              }
              html.nodeseek-private-message-page body,
              html.nodeseek-profile-page body {
                overflow-x: hidden !important;
                max-width: 100vw !important;
              }
              html.nodeseek-private-message-page #nsk-body-left *,
              html.nodeseek-profile-page #nsk-body-left * {
                max-width: 100% !important;
                box-sizing: border-box !important;
              }              html.nodeseek-private-message-page footer,
              html.nodeseek-profile-page footer,
              html.nodeseek-private-message-page #fast-nav-button-group,
              html.nodeseek-profile-page #fast-nav-button-group {
                display: none !important;
              }
              html.nodeseek-private-message-page #nsk-body-left,
              html.nodeseek-profile-page #nsk-body-left {
                min-height: 100vh !important;
              }              html.nodeseek-private-message-page #nsk-body-left {
                padding: 0 16px 140px !important;
                background: #eef0f3 !important;
                border-left: 1px solid rgba(0, 0, 0, 0.06) !important;
                border-right: 1px solid rgba(0, 0, 0, 0.06) !important;
              }
              html.nodeseek-private-message-page [class*="message"] :is(article, [class*="bubble"], [class*="content"]),
              html.nodeseek-private-message-page [class*="conversation"] :is(article, [class*="bubble"], [class*="content"]) {
                max-width: 78% !important;
                margin: 6px 0 !important;
                border: 1px solid #d7dbe2 !important;
                border-radius: 12px !important;
                padding: 8px 12px !important;
                box-sizing: border-box !important;
              }
              html.nodeseek-private-message-page [class*="message"][class*="self"],
              html.nodeseek-private-message-page [class*="message"][class*="own"],
              html.nodeseek-private-message-page [class*="message"][class*="mine"],
              html.nodeseek-private-message-page [class*="bubble"][class*="right"],
              html.nodeseek-private-message-page [class*="chat"] [class*="right"] {
                align-self: flex-end !important;
                margin-left: auto !important;
                margin-right: 0 !important;
              }
              html.nodeseek-private-message-page [class*="message"][class*="self"] :is(article, [class*="bubble"], [class*="content"]),
              html.nodeseek-private-message-page [class*="message"][class*="own"] :is(article, [class*="bubble"], [class*="content"]),
              html.nodeseek-private-message-page [class*="message"][class*="mine"] :is(article, [class*="bubble"], [class*="content"]),
              html.nodeseek-private-message-page [class*="chat"] [class*="right"] :is(article, [class*="bubble"], [class*="content"]) {
                background: #95ec69 !important;
                border-color: #7fd45a !important;
              }              html.nodeseek-private-message-page table,
              html.nodeseek-profile-page table {
                width: 100% !important;
                max-width: 100% !important;
                table-layout: fixed !important;
              }              input:not([type="checkbox"]):not([type="radio"]),
              textarea,
              select {
                font-size: ${inputFontSize}px !important;
                line-height: 1.35 !important;
                box-sizing: border-box !important;
              }
              [role="tablist"],
              .tabs,
              [class*="tabs"],
              .el-tabs__nav,
              .el-tabs__header,
              .nav-tabs,
              .nav-pills,
              .notification-tabs,
              .notifications-nav,
              [class*="notification-tab"] {
                display: flex !important;
                flex-wrap: wrap !important;
                align-items: stretch !important;
                gap: 4px !important;
                height: auto !important;
                min-height: 44px !important;
                white-space: normal !important;
              }
              [role="tab"],
              .tabs > *,
              [class*="tabs"] > *,
              .el-tabs__item,
              .nav-tabs > *,
              .nav-pills > *,
              .notification-tabs > *,
              .notifications-nav > *,
              [class*="notification-tab"] > * {
                min-height: 40px !important;
                padding: 8px 12px !important;
                font-size: 16px !important;
                line-height: 1.35 !important;
                white-space: nowrap !important;
                box-sizing: border-box !important;
              }
              [class*="message"] p,
              [class*="message"] a,
              [id*="message"] p,
              [id*="message"] a,
              [class*="chat"] p,
              [class*="chat"] a,
              [class*="profile"] a,
              [class*="contact"] a {
                font-size: ${messageFontSize}px !important;
                line-height: 1.5 !important;
                overflow-wrap: anywhere !important;
              }
              html.nodeseek-private-message-page [class*="message"],
              html.nodeseek-private-message-page [class*="chat"],
              html.nodeseek-private-message-page [class*="conversation"] {
                line-height: 1.5 !important;
              }
              html.nodeseek-private-message-page [class*="message"] :is(p, span, a, li),
              html.nodeseek-private-message-page [class*="chat"] :is(p, span, a, li),
              html.nodeseek-private-message-page [class*="conversation"] :is(p, span, a, li) {
                font-size: ${messageFontSize}px !important;
                line-height: 1.5 !important;
              }
              [class*="message"] button,
              [class*="message"] input,
              [class*="message"] textarea,
              [class*="chat"] button,
              [class*="chat"] input,
              [class*="chat"] textarea {
                min-height: 40px !important;
              }
              h1, h2, h3, h4, h5, h6 {
                line-height: 1.25 !important;
                overflow-wrap: anywhere !important;
              }
            `;
            ensureViewport();
            scheduleMobilePageRefresh();
          };
          window.__nodeSeekApplyDisplayScale = apply;
          const observedRoot = document.documentElement;
          if (observedRoot) {
            const observer = new MutationObserver(scheduleMobilePageRefresh);
            observer.observe(observedRoot, { childList: true, subtree: true });
          }
          window.addEventListener('hashchange', scheduleMobilePageRefresh);
          window.addEventListener('popstate', scheduleMobilePageRefresh);
          apply(\(normalizedScaleLiteral(scale)));
        })();
        """
    }

    private static func normalizedScaleLiteral(_ rawScale: CGFloat) -> String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            AppDisplayScaleSettings.normalizedScale(rawScale)
        )
    }
}
