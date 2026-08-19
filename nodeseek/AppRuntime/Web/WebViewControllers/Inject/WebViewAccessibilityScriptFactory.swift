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
              viewport.setAttribute('content', 'width=device-width, initial-scale=1, viewport-fit=cover');
            }
          };
          const apply = (rawScale) => {
            const scale = Math.min(1.2, Math.max(0.7, Number(rawScale) || 1));
            const root = document.documentElement;
            if (!root) return;
            root.style.setProperty('--nodeseek-display-scale', String(scale));
            root.style.setProperty('font-size', `${16 * scale}px`, 'important');
            let style = document.getElementById(styleID);
            if (!style) {
              style = document.createElement('style');
              style.id = styleID;
              (document.head || root).appendChild(style);
            }
            // iOS 会在输入控件字体小于 16px 时自动放大页面。保持控件最小字号可避免私信输入时跳变。
            style.textContent = `
              input:not([type="checkbox"]):not([type="radio"]),
              textarea,
              select {
                font-size: max(16px, calc(16px * var(--nodeseek-display-scale))) !important;
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
