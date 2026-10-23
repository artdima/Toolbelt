//
//  LinkedInModels.swift
//  Toolbelt
//
//  What LinkedIn answers, the post Toolbelt sends, and what a check makes of them.
//

import Foundation

nonisolated enum LinkedInVisibility: String, Codable, CaseIterable, Sendable {
    case `public` = "PUBLIC"
    case connections = "CONNECTIONS"

    init?(argument: String) {
        self.init(rawValue: argument.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    var audience: String {
        switch self {
        case .public: "visible to everyone"
        case .connections: "visible to connections"
        }
    }
}

/// `GET /v2/userinfo` of Sign In with LinkedIn using OpenID Connect.
nonisolated struct LinkedInUserInfo: Decodable, Equatable, Sendable {
    let sub: String
    let name: String?
    let givenName: String?
    let familyName: String?
    let picture: String?
    let locale: LinkedInLocale?
    let email: String?
    let emailVerified: Bool?

    var authorURN: String { "urn:li:person:\(sub)" }

    var displayName: String? {
        if let name, !name.isEmpty { return name }
        let parts = [givenName, familyName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// The docs show "en-US"; some answers carry {"language": "en", "country": "US"} instead.
nonisolated struct LinkedInLocale: Decodable, Equatable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            value = text
            return
        }
        let container = try decoder.container(keyedBy: Keys.self)
        let language = try container.decodeIfPresent(String.self, forKey: .language)
        let country = try container.decodeIfPresent(String.self, forKey: .country)
        value = [language, country].compactMap { $0 }.joined(separator: "-")
    }

    private enum Keys: String, CodingKey {
        case language
        case country
    }
}

/// `POST /oauth/v2/introspectToken`. A token LinkedIn does not know for this app comes back
/// as {"active": false} and nothing else.
nonisolated struct LinkedInIntrospection: Decodable, Equatable, Sendable {
    let active: Bool
    let status: String?
    let expiresAt: Double?
    let scope: String?

    init(active: Bool, status: String? = nil, expiresAt: Double? = nil, scope: String? = nil) {
        self.active = active
        self.status = status
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// The docs separate scopes with commas; spaces are accepted too.
    var scopes: [String]? {
        scope.map { value in
            value.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        }
    }

    var expiry: MCPTokenExpiry {
        guard active, let expiresAt else { return .unknown }
        return .on(Date(timeIntervalSince1970: expiresAt))
    }
}

nonisolated struct LinkedInErrorBody: Decodable, Sendable {
    let message: String?
    let code: String?
    let error: String?
    let errorDescription: String?
}

nonisolated struct LinkedInDistribution: Encodable, Equatable, Sendable {
    let feedDistribution = "MAIN_FEED"
    let targetEntities: [String] = []
    let thirdPartyDistributionChannels: [String] = []
}

/// A text post on the member's own feed, as the Posts API documents it.
nonisolated struct LinkedInPostBody: Encodable, Equatable, Sendable {
    let author: String
    let commentary: String
    let visibility: LinkedInVisibility
    let distribution = LinkedInDistribution()
    let lifecycleState = "PUBLISHED"
    let isReshareDisabledByAuthor = false

    init(author: String, commentary: String, visibility: LinkedInVisibility) {
        self.author = author
        self.commentary = commentary
        self.visibility = visibility
    }
}

/// What Check in the editor makes of the two answers.
nonisolated enum LinkedInSetupCheck {
    static let shareScope = "w_member_social"

    static func account(
        userInfo: LinkedInUserInfo,
        introspection: LinkedInIntrospection?,
        checkedAt: Date
    ) -> MCPAccount {
        MCPAccount(
            username: userInfo.email ?? "",
            displayName: userInfo.displayName,
            subjectID: userInfo.sub,
            tokenName: nil,
            scopes: introspection?.active == true ? introspection?.scopes : nil,
            expiry: introspection?.expiry ?? .unknown,
            checkedAt: checkedAt
        )
    }

    static func warnings(account: MCPAccount, introspection: LinkedInIntrospection?, now: Date = Date()) -> [String] {
        var warnings: [String] = []
        if let introspection {
            if let status = introspection.status?.lowercased(), status == "expired" || status == "revoked" {
                warnings.append("LinkedIn reports the token as \(status).")
            } else if !introspection.active {
                warnings.append(
                    "LinkedIn does not know this token for this Client ID: the token was issued for another app. "
                        + "Generate it for the app whose Client ID and Client Secret are above."
                )
            }
        }
        if let scopes = account.scopes, !scopes.contains(shareScope) {
            warnings.append(
                "The token has no \(shareScope) scope, so posting fails even with Allow write on. "
                    + "Add the Share on LinkedIn product to the app and generate the token again."
            )
        }
        if account.isExpired(now: now) {
            warnings.append("The token has expired.")
        } else if account.expiresSoon(now: now), let days = account.daysLeft(now: now) {
            warnings.append("The token expires in \(days) \(days == 1 ? "day" : "days").")
        }
        return warnings
    }
}
