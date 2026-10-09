//
//  NodeSeekCookieSession.swift
//  nodeseek
//

import UIKit

@MainActor
protocol NodeSeekCookieSessionManaging: AnyObject {
    func prepareWebViewLoad(userInterfaceStyle: UIUserInterfaceStyle?) async
    func captureWebViewSession() async
    func prepareHTTPLoad() async
    func prepareMediaRequest() async
    func clearLoginSession() async
}

extension NodeSeekCookieSessionManaging {
    func prepareWebViewLoad() async {
        await prepareWebViewLoad(userInterfaceStyle: nil)
    }
}

@MainActor
final class NodeSeekCookieSession: NodeSeekCookieSessionManaging {
    private let bridge: CookieBridge
    private let webCookieStore: WebCookieStore?
    /// 只有走系统全局存储（WKWebsiteDataStore.default + HTTPCookieStorage.shared）
    /// 的实例才参与节流：全局窗口对注入的自定义存储不成立，会把测试和隔离
    /// 数据源的同步错误地跳过。默认 false = 永远真同步。
    private let allowsSyncThrottle: Bool

    convenience init(webCookieStore: WebCookieStore? = nil) {
        // 只有不传 store 的构造才对应系统全局存储（WKWebsiteDataStore.default
        // + HTTPCookieStorage.shared），也只有它适用全局同步窗口。
        self.init(
            bridge: CookieBridge(webCookieStore: webCookieStore),
            webCookieStore: webCookieStore,
            allowsSyncThrottle: webCookieStore == nil
        )
    }

    init(
        bridge: CookieBridge,
        webCookieStore: WebCookieStore? = nil,
        allowsSyncThrottle: Bool = false
    ) {
        self.bridge = bridge
        self.webCookieStore = webCookieStore
        self.allowsSyncThrottle = allowsSyncThrottle
    }

    func prepareWebViewLoad(userInterfaceStyle: UIUserInterfaceStyle?) async {
        await bridge.syncURLSessionCookiesToWebView()
        guard let userInterfaceStyle, let webCookieStore else { return }
        await NodeSeekWebThemeSupport.syncPreferredColorSchemeCookie(
            to: webCookieStore,
            userInterfaceStyle: userInterfaceStyle
        )
    }

    func captureWebViewSession() async {
        // 这条路是"WebView 刚拿到新 cookie"（登录、过质询、页面动作回抓），
        // 必须无条件落到 URLSession，否则表现为登录了却仍是未登录。
        await bridge.syncWebViewCookiesToURLSession(throttled: false)
    }

    func prepareHTTPLoad() async {
        await bridge.syncWebViewCookiesToURLSession(throttled: allowsSyncThrottle)
    }

    func prepareMediaRequest() async {
        await bridge.syncWebViewCookiesToURLSession(throttled: allowsSyncThrottle)
    }

    func clearLoginSession() async {
        await bridge.clearSession()
    }
}
