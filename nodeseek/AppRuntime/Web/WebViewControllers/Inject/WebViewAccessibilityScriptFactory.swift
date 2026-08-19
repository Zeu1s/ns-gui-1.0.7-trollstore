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
            root.classList.toggle(
              'nodeseek-private-message-page',
              `${window.location.pathname}${window.location.hash}`.toLowerCase().includes('/message')
            );
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
              input:not([type="checkbox"]):not([type="radio"]),
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
          };
          window.__nodeSeekApplyDisplayScale = apply;
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
