//
//  YandexOAuth.swift
//  Toolbelt
//
//  Getting a Tracker token from Yandex OAuth with the app's ClientID alone: the
//  token comes back in the fragment of the redirect, no client secret involved.
//

import Foundation

enum YandexOAuth {
    /// The redirect of an app made "for API access or debugging".
    static let redirectURI = "https://oauth.yandex.ru/verification_code"
    static let scopes = ["tracker:read", "tracker:write"]

    enum Outcome: Equatable {
        case token(String, expiresIn: TimeInterval?)
        case failure(code: String, description: String?)
    }

    /// Without `redirect_uri` Yandex sends the user to the one registered for the app,
    /// so a token is caught whatever address the app was set up with.
    static func authorizeURL(clientID: String, state: String) -> URL? {
        var components = URLComponents(string: "https://oauth.yandex.ru/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }

    /// `nil` for every page on the way: sign-in, consent, and anything that is not
    /// the answer to this very request.
    static func outcome(of url: URL, state: String) -> Outcome? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
              !fragment.isEmpty,
              let items = URLComponents(string: "?" + fragment)?.queryItems
        else { return nil }

        var values: [String: String] = [:]
        for item in items {
            values[item.name] = item.value
        }

        if let returnedState = values["state"], returnedState != state {
            return nil
        }

        if let token = values["access_token"], !token.isEmpty {
            return .token(token, expiresIn: values["expires_in"].flatMap { TimeInterval($0) })
        }
        if let code = values["error"], !code.isEmpty {
            let description = values["error_description"]?.replacingOccurrences(of: "+", with: " ")
            return .failure(code: code, description: description)
        }
        return nil
    }

    static func message(forError code: String, description: String?) -> String {
        switch code {
        case "access_denied":
            return "Access was not allowed, so Yandex issued no token."
        case "invalid_scope":
            return "The app has no Tracker permissions. On oauth.yandex.ru give it "
                + "“Read from tracker” and “Write to tracker”, then try again."
        case "unauthorized_client":
            return "Yandex has blocked this app or not approved it yet. Create a new one on oauth.yandex.ru."
        default:
            if let description, !description.isEmpty {
                return "Yandex OAuth: \(description)"
            }
            return "Yandex OAuth returned the error “\(code)”."
        }
    }
}
