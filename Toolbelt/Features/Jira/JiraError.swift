//
//  JiraError.swift
//  Toolbelt
//

import Foundation

enum JiraError: LocalizedError, Equatable {
    case missingSite
    case invalidSite
    case missingEmail
    case missingToken
    case invalidURL
    case unexpectedResponse
    case redirected(location: String)
    case webPage
    case unauthorized
    case forbidden
    case notFound
    case http(status: Int, message: String)
    case decoding(String)
    case unknownUser

    static func from(status: Int, body: String) -> JiraError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        default: return .http(status: status, message: message(from: body))
        }
    }

    /// A sign-in page or a proxy's error page comes back as HTML with status 200.
    static func isWebPage(contentType: String?) -> Bool {
        guard let contentType = contentType?.lowercased() else { return false }
        return !contentType.contains("json")
    }

    /// Jira explains a rejected request in `errorMessages` and `errors`; any other body is kept as is.
    static func message(from body: String) -> String {
        struct Payload: Decodable {
            let errorMessages: [String]?
            let errors: [String: String]?
        }

        if let payload = try? JSONDecoder().decode(Payload.self, from: Data(body.utf8)) {
            let fieldErrors = (payload.errors ?? [:])
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
            let messages = (payload.errorMessages ?? []) + fieldErrors
            if !messages.isEmpty {
                return messages.joined(separator: " ")
            }
        }
        return String(body.prefix(300))
    }

    var errorDescription: String? {
        switch self {
        case .missingSite:
            return "No Jira site address set. Open Settings."
        case .invalidSite:
            return "The Jira site address is not an https address. Open Settings."
        case .missingEmail:
            return "No account email set. Open Settings."
        case .missingToken:
            return "No API token set. Open Settings."
        case .invalidURL:
            return "Malformed request URL"
        case .unexpectedResponse:
            return "Unexpected response from the server"
        case let .redirected(location):
            return "3xx: redirected to \(location)"
        case .webPage:
            return "The site answered with a web page instead of JSON"
        case .unauthorized:
            return "401: the credentials are wrong or the token has expired"
        case .forbidden:
            return "403: access denied"
        case .notFound:
            return "404: not found"
        case let .http(status, message):
            return message.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(message)"
        case let .decoding(details):
            return "Could not parse the Jira response: \(details)"
        case .unknownUser:
            return "Could not determine the current Jira user"
        }
    }
}
