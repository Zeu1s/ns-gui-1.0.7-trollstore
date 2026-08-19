//
//  NodeSeekWebViewContext.swift
//  nodeseek
//

import UIKit
import WebKit

@MainActor
final class NodeSeekWebViewContext {
    let webView: WKWebView

    private let cookieSession: NodeSeekCookieSessionManaging

    init(
        additionalUserScripts: [WKUserScript] = [],
        cookieSession: NodeSeekCookieSessionManaging? = nil
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let userScripts = [WebViewAccessibilityScriptFactory.makeDisplayScaleScript()] + additionalUserScripts
        configuration.userContentController = NodeSeekWebThemeSupport.makeUserContentController(
            additionalScripts: userScripts
        )

        let webCookieStore = WKWebCookieStoreAdapter(
            store: configuration.websiteDataStore.httpCookieStore
        )
        self.webView = NoBounceWebView(frame: .zero, configuration: configuration)
        self.cookieSession = cookieSession ?? NodeSeekCookieSession(webCookieStore: webCookieStore)
    }

    func prepareForInitialLoad(userInterfaceStyle: UIUserInterfaceStyle) async {
        await cookieSession.prepareWebViewLoad(userInterfaceStyle: userInterfaceStyle)
    }

    func captureWebViewSession() async {
        await cookieSession.captureWebViewSession()
    }
}
