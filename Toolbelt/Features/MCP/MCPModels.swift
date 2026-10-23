//
//  MCPModels.swift
//  Toolbelt
//
//  Resources Claude reaches through Toolbelt, and what is known about their tokens.
//

import Foundation

nonisolated enum MCPResourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gitlab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gitlab: "GitLab"
        }
    }
}

nonisolated enum MCPTokenExpiry: Codable, Equatable, Sendable {
    case unknown
    case never
    case on(Date)
}

/// The user and the token as the service reported them on the last check.
nonisolated struct MCPAccount: Codable, Equatable, Sendable {
    var username: String
    var displayName: String?
    /// The service's own id of the user, where tools need it: LinkedIn builds the post author from it.
    var subjectID: String?
    var tokenName: String?
    var scopes: [String]?
    var expiry: MCPTokenExpiry
    var checkedAt: Date

    static let expiryWarningDays = 14

    /// Whole days until the token stops working; negative once it has.
    func daysLeft(now: Date = Date()) -> Int? {
        guard case let .on(date) = expiry else { return nil }
        return Int((date.timeIntervalSince(now) / 86_400).rounded(.down))
    }

    func isExpired(now: Date = Date()) -> Bool {
        guard case let .on(date) = expiry else { return false }
        return now >= date
    }

    func expiresSoon(now: Date = Date()) -> Bool {
        guard let days = daysLeft(now: now), !isExpired(now: now) else { return false }
        return days < Self.expiryWarningDays
    }
}

nonisolated struct MCPResource: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: MCPResourceKind
    var name: String
    var baseURL: URL
    /// The OAuth app the token was issued for, where the service has one; its secret is in Keychain.
    var clientID: String?
    var isEnabled = true
    var allowWrite = false
    var account: MCPAccount?

    var host: String {
        guard let host = baseURL.host(percentEncoded: false) else { return baseURL.absoluteString }
        if let port = baseURL.port { return "\(host):\(port)" }
        return host
    }

    /// Only https leaves the machine; plain http is accepted for a server on this Mac.
    static func validatedBaseURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty,
              url.query == nil, url.fragment == nil, url.user == nil
        else { return nil }

        switch scheme {
        case "https":
            return url
        case "http":
            return ["localhost", "127.0.0.1", "::1"].contains(host) ? url : nil
        default:
            return nil
        }
    }
}

nonisolated struct MCPCallLogEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let client: String
    let tool: String
    let arguments: String
    let isError: Bool
    let duration: TimeInterval
    let responseSize: Int
}
