//
//  NodeSeekMemberProfileResolver.swift
//  nodeseek
//

import Foundation

nonisolated enum NodeSeekMemberProfileResolverError: LocalizedError {
    case invalidURL
    case missingUserID
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "用户资料链接无效。"
        case .missingUserID:
            return "无法解析用户 ID。"
        case .httpStatus(let statusCode):
            return "用户资料请求失败（\(statusCode)）。"
        }
    }
}

/// 将站内 /member?t=用户名 链接解析为数字用户 ID，用于打开原生资料页。
nonisolated enum NodeSeekMemberProfileResolver {
    private static let spaceUIDPattern = try! NSRegularExpression(
        pattern: #"/space/(\d+)"#,
        options: [.caseInsensitive]
    )
    private static let anchorUIDPattern = try! NSRegularExpression(
        pattern: #"(?:href|src|data-uid)\s*[=:]\s*["']?n(\d+)"#,
        options: [.caseInsensitive]
    )
    private static let jsonUIDPattern = try! NSRegularExpression(
        pattern: #"(?:member_id|memberID|uid|userId|user_id)\s*[:=]\s*["']?(\d+)"#,
        options: [.caseInsensitive]
    )

    static func memberUsername(from url: URL) -> String? {
        let path = url.path.lowercased()
        guard path == "/member" || path == "/member/" else { return nil }
        guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == "t" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            raw.isEmpty == false else {
            return nil
        }
        return raw
    }

    static func resolveUserID(username: String) async throws -> Int {
        guard let url = memberURL(for: username) else {
            throw NodeSeekMemberProfileResolverError.invalidURL
        }
        await NodeSeekCookieSession().prepareHTTPLoad()
        let response = try await HTTPHTMLClient().get(url)
        guard (200..<300).contains(response.statusCode) else {
            throw NodeSeekMemberProfileResolverError.httpStatus(response.statusCode)
        }
        if let userID = uid(from: response.finalURL) {
            return userID
        }
        if let userID = uid(from: response.html) {
            return userID
        }
        throw NodeSeekMemberProfileResolverError.missingUserID
    }

    private static func memberURL(for username: String) -> URL? {
        var components = URLComponents(
            url: NodeSeekSite.baseURL.appendingPathComponent("member"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "t", value: username)]
        return components?.url
    }

    private static func uid(from url: URL) -> Int? {
        if let userID = NodeSeekUserIDResolver.uid(from: url) {
            return userID
        }
        return uid(from: url.path, pattern: spaceUIDPattern)
    }

    private static func uid(from html: String) -> Int? {
        for pattern in [spaceUIDPattern, anchorUIDPattern, jsonUIDPattern] {
            if let userID = uid(from: html, pattern: pattern) {
                return userID
            }
        }
        return nil
    }

    private static func uid(from source: String, pattern: NSRegularExpression) -> Int? {
        let fullRange = NSRange(source.startIndex..., in: source)
        for match in pattern.matches(in: source, options: [], range: fullRange) {
            guard match.numberOfRanges >= 2,
                  let idRange = Range(match.range(at: 1), in: source),
                  let userID = Int(source[idRange]),
                  userID > 0 else {
                continue
            }
            return userID
        }
        return nil
    }
}