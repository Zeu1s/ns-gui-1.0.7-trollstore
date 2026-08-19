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
          const ensureViewport = (scale) => {
            let viewport = document.querySelector('meta[name="viewport"]');
            if (!viewport) {
              viewport = document.createElement('meta');
              viewport.name = 'viewport';
              document.head && document.head.appendChild(viewport);
            }
            if (viewport) {
              viewport.setAttribute(
                'content',
                `width=device-width, initial-scale=${scale}, minimum-scale=${scale}, maximum-scale=${scale}, user-scalable=no, viewport-fit=cover`
              );
            }
          };
          const apply = (rawScale) => {
            const scale = Math.min(1.2, Math.max(0.7, Number(rawScale) || 1));
            const inputFontSize = 16;
            const messageFontSize = 17;
            const root = document.documentElement;
            if (!root) return;
            root.style.setProperty('--nodeseek-display-scale', String(scale));
            root.style.setProperty('font-size', '16px', 'important');
            let style = document.getElementById(styleID);
            if (!style) {
              style = document.createElement('style');
              style.id = styleID;
              (document.head || root).appendChild(style);
            }
            // iOS 会在输入控件字体小于 16px 时自动放大页面。保持控件最小字号可避免私信输入时跳变。
            style.textContent = `
              html {
                overflow-x: hidden !important;
              }
              body {
                zoom: 1 !important;
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
                line-height: 1.35 !important;
                white-space: nowrap !important;
                box-sizing: border-box !important;
              }
              [class*="message"] p,
              [class*="message"] a,
              [id*="message"] p,
              [id*="message"] a,
              [class*="profile"] a,
              [class*="contact"] a {
                font-size: ${messageFontSize}px !important;
                line-height: 1.5 !important;
                overflow-wrap: anywhere !important;
              }
              [class*="message"] button,
              [class*="message"] input,
              [class*="message"] textarea {
                min-height: 40px !important;
              }
              h1, h2, h3, h4, h5, h6 {
                line-height: 1.25 !important;
                overflow-wrap: anywhere !important;
              }
            `;
            ensureViewport(scale);
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
