//
//  HTMLLoadingStrategy.swift
//  nodeseek
//

import Foundation

enum HTMLLoadingStrategy: Sendable {
    case legacyWebView
    case httpWithWebViewFallback
}

@MainActor
enum HTMLLoadingStrategyConfig {
    static var listAndDetailStrategy: HTMLLoadingStrategy = .httpWithWebViewFallback
}

@MainActor
enum HTMLLoadingStrategyFactory {
    static func makeDefaultClient() -> any HTMLClient {
        makeClient(strategy: HTMLLoadingStrategyConfig.listAndDetailStrategy)
    }

    static func makeClient(strategy: HTMLLoadingStrategy) -> any HTMLClient {
        switch strategy {
        case .legacyWebView:
            AppLog.info(.service, "HTML加载策略=legacyWebView")
            return HiddenWebViewHTMLClient()
        case .httpWithWebViewFallback:
            AppLog.info(.service, "HTML加载策略=httpWithWebViewFallback")
            return WebViewFallbackHTMLClient(
                primaryClient: HTTPHTMLClient(),
                fallbackClient: HiddenWebViewHTMLClient(),
                cookieSession: NodeSeekCookieSession()
            )
        }
    }
}

struct WebViewFallbackHTMLClient: HTMLClient, WebViewFallbackRetrying {
    private let primaryClient: any HTMLClient
    private let fallbackClient: any HTMLClient
    private let cookieSession: NodeSeekCookieSessionManaging?
    private let challengeDetector: ChallengeDetector

    init(
        primaryClient: any HTMLClient,
        fallbackClient: any HTMLClient,
        cookieSession: NodeSeekCookieSessionManaging?,
        challengeDetector: ChallengeDetector = ChallengeDetector()
    ) {
        self.primaryClient = primaryClient
        self.fallbackClient = fallbackClient
        self.cookieSession = cookieSession
        self.challengeDetector = challengeDetector
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        await prepareCookiesForHTTPLoad(reason: "primary-before-get", url: url)
        AppLog.info(.service, "HTTP优先加载开始 method=GET url=\(url.absoluteString)")
        let primaryResponse: HTMLResponse
        do {
            primaryResponse = try await primaryClient.get(url)
        } catch {
            guard Task.isCancelled == false, Self.isCancelledRequest(error) == false else {
                throw error
            }
            AppLog.warning(.service, "HTTP请求失败，尝试 WebView 会话恢复: \(error.localizedDescription)")
            return try await fallbackAfterPrimaryFailure(url: url, primaryError: error)
        }
        // 一份响应只判定一次：detect 会对整页 HTML 做多轮全文扫描，
        // 之前在同一次加载里被调了 3 遍。
        let primaryChallenge = challengeDetector.detect(response: primaryResponse)
        log(response: primaryResponse, phase: "primary", challenge: primaryChallenge)

        guard shouldFallback(challenge: primaryChallenge) else {
            return primaryResponse
        }

        return try await fallbackAndRetryGet(
            url: url,
            primaryResponse: primaryResponse,
            primaryChallenge: primaryChallenge
        )
    }

    private func fallbackAfterPrimaryFailure(url: URL, primaryError: Error) async throws -> HTMLResponse {
        let fallbackResponse: HTMLResponse
        do {
            fallbackResponse = try await fallbackClient.get(url)
        } catch {
            AppLog.error(
                .service,
                "HTTP请求与 WebView 恢复均失败，保留原始错误: http=\(primaryError.localizedDescription), webView=\(error.localizedDescription)"
            )
            throw primaryError
        }
        log(response: fallbackResponse, phase: "webview-network-recovery")
        guard Task.isCancelled == false else { throw CancellationError() }
        await prepareCookiesForHTTPLoad(reason: "after-webview-network-recovery", url: url)
        guard Task.isCancelled == false else { throw CancellationError() }

        do {
            let retryResponse = try await primaryClient.get(url)
            log(response: retryResponse, phase: "network-recovery-retry")
            if challengeDetector.detect(response: retryResponse) == nil {
                return retryResponse
            }
        } catch {
            AppLog.warning(.service, "WebView 恢复后 HTTP 重试失败，使用 WebView 页面: \(error.localizedDescription)")
        }
        return fallbackResponse
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        await prepareCookiesForHTTPLoad(reason: "primary-before-post", url: url)
        AppLog.info(.service, "HTTP优先加载开始 method=POST url=\(url.absoluteString)")
        let response = try await primaryClient.post(url, formFields: formFields)
        log(response: response, phase: "primary-post")
        return response
    }

    /// HTTP 已经拿到响应、但业务解析失败时，直接使用 WebView 的页面结果。
    /// 此时重试 HTTP 往往仍会得到同一份被中间页替换的内容，反而掩盖可用的 WebView 结果。
    func getUsingWebViewFallback(_ url: URL) async throws -> HTMLResponse {
        AppLog.warning(.service, "详情解析失败，直接使用 WebView 回退加载: \(url.absoluteString)")
        let response = try await fallbackClient.get(url)
        log(response: response, phase: "webview-parse-recovery")
        await prepareCookiesForHTTPLoad(reason: "after-webview-parse-recovery", url: url)
        return response
    }

    private func fallbackAndRetryGet(
        url: URL,
        primaryResponse: HTMLResponse,
        primaryChallenge: ChallengeKind?
    ) async throws -> HTMLResponse {
        if let challenge = primaryChallenge {
            AppLog.warning(.service, "HTTP命中验证，准备 WebView fallback: \(challenge.logDescription)")
        }

        let fallbackResponse: HTMLResponse
        do {
            fallbackResponse = try await fallbackClient.get(url)
        } catch {
            AppLog.error(.service, "WebView fallback 失败，返回 HTTP 原始结果: \(error.localizedDescription)")
            return primaryResponse
        }
        log(response: fallbackResponse, phase: "webview-fallback")

        // WebView 已经拿到可用的完整页面，直接采用；再重试一次 HTTP 只会得到
        // 同一份被 Cloudflare 指纹封锁的拦截页（403），用失败覆盖成功反而丢失结果。
        guard challengeDetector.detect(response: fallbackResponse) == nil else {
            AppLog.warning(.service, "WebView fallback 仍命中验证，保留 HTTP 原始结果: \(url.absoluteString)")
            return primaryResponse
        }

        await prepareCookiesForHTTPLoad(reason: "after-webview-fallback", url: url)
        return fallbackResponse
    }

    private static func isCancelledRequest(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func shouldFallback(challenge: ChallengeKind?) -> Bool {
        guard let challenge else {
            return false
        }

        switch challenge {
        case .cloudflare, .blocked:
            return true
        case .httpError(let status, _):
            // 4xx/5xx 是站点对这个请求本身的回应，换 WebView 重发同一个请求
            // 大概率还是同样的错；而 WebView 回退要占全局请求锁（实测单次
            // 14~21 秒），拿它换一个必然失败的尝试不划算。直接如实报错。
            AppLog.warning(.service, "站点返回错误状态码 \(status)，跳过 WebView 回退: \(challenge.logDescription)")
            return false
        case .rateLimited:
            // 限流时再走 WebView 只会延续限流窗口，直接上抛让调用方退避。
            AppLog.warning(.service, "HTTP 命中站点限流(429)，跳过 WebView fallback: \(challenge.logDescription)")
            return false
        case .loginRequired, .unsupported:
            AppLog.info(.service, "HTTP命中非 fallback 验证，保持原结果: \(challenge.logDescription)")
            return false
        }
    }

    private func prepareCookiesForHTTPLoad(reason: String, url: URL) async {
        guard let cookieSession else { return }
        AppLog.info(.service, "准备 HTTP Cookie reason=\(reason) url=\(url.absoluteString)")
        await cookieSession.prepareHTTPLoad()
    }

    private func log(response: HTMLResponse, phase: String) {
        log(response: response, phase: phase, challenge: challengeDetector.detect(response: response))
    }

    private func log(response: HTMLResponse, phase: String, challenge: ChallengeKind?) {
        AppLog.info(
            .service,
            "HTML加载结果 phase=\(phase) status=\(response.statusCode) htmlLength=\(response.html.count) finalURL=\(response.finalURL.absoluteString) challenge=\(challenge?.logDescription ?? "none")"
        )
    }
}
