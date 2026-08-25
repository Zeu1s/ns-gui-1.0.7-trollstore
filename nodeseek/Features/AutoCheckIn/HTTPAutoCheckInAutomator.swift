//
//  HTTPAutoCheckInAutomator.swift
//  nodeseek
//

import Foundation

@MainActor
final class HTTPAutoCheckInAutomator: AutoCheckInWebAutomating {
    private let session: URLSession
    private let baseURL: URL
    private let cookiePreparer: @Sendable () async -> Void

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        cookiePreparer: @escaping @Sendable () async -> Void = {
            await NodeSeekCookieSession().prepareHTTPLoad()
        }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
    }

    func fetchBoardState(runID: String) async throws -> AutoCheckInBoardState {
        let request = makeRequest(path: "/api/attendance/board", queryItems: [URLQueryItem(name: "page", value: "1")])
        let (data, response) = try await perform(request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            return AutoCheckInBoardState(
                ok: false,
                isLoggedIn: false,
                isCheckedIn: false,
                message: "签到状态返回异常。",
                detectionSource: "invalid_json",
                reason: "invalid_board_payload",
                statusCode: statusCode,
                responseKeys: []
            )
        }

        let message = firstString(in: payload, keys: ["message", "msg", "error"])
        let isSuccessfulStatus = statusCode.map { (200..<300).contains($0) } ?? false
        let isCheckedIn = hasCurrentRecord(in: payload)
        let isLoggedIn = isSuccessfulStatus && isLoginMessage(message) == false
        return AutoCheckInBoardState(
            ok: isSuccessfulStatus,
            isLoggedIn: isLoggedIn,
            isCheckedIn: isCheckedIn,
            message: message,
            detectionSource: isCheckedIn ? "board_current_record" : "board_api",
            reason: isSuccessfulStatus ? "loaded" : "server_error",
            statusCode: statusCode,
            responseKeys: payload.keys.sorted()
        )
    }

    func submit(mode: AutoCheckInMode, runID: String) async throws -> AutoCheckInSubmitResult {
        let request = makeRequest(
            path: "/api/attendance",
            queryItems: [URLQueryItem(name: "random", value: mode.randomQueryValue)],
            method: "POST"
        )
        let (data, response) = try await perform(request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let success = boolValue(payload["success"])
        let message = firstString(in: payload, keys: ["message", "msg", "error"])
        return AutoCheckInSubmitResult(
            ok: statusCode.map { (200..<300).contains($0) } == true && success == true,
            statusCode: statusCode,
            success: success,
            message: message,
            current: intValue(payload["current"]),
            reason: success == true ? "submitted" : "server_error"
        )
    }

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET"
    ) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent(path))
        request.httpMethod = method
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: NodeSeekSite.boardURL)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        await cookiePreparer()
        return try await session.data(for: request)
    }

    private func hasCurrentRecord(in payload: [String: Any]) -> Bool {
        let values = [payload["record"], payload["memberList"]]
        for value in values {
            if let record = value as? [String: Any], record.isEmpty == false {
                return true
            }
            if let records = value as? [[String: Any]], records.contains(where: isCurrentRecord) {
                return true
            }
            if let records = value as? [Any], records.compactMap({ $0 as? [String: Any] }).contains(where: isCurrentRecord) {
                return true
            }
        }
        return false
    }

    private func isCurrentRecord(_ value: [String: Any]) -> Bool {
        ["current", "isCurrent", "self", "isSelf", "mine"].contains { boolValue(value[$0]) == true }
    }

    private func firstString(in payload: [String: Any], keys: [String]) -> String? {
        keys.compactMap { payload[$0] as? String }.first { $0.isEmpty == false }
    }

    private func isLoginMessage(_ message: String?) -> Bool {
        let normalized = message?.lowercased() ?? ""
        return normalized.contains("user not found") || normalized.contains("not login") || normalized.contains("未登录")
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
