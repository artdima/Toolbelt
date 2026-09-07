//
//  TrackerError.swift
//  Toolbelt
//

import Foundation

enum TrackerError: LocalizedError, Equatable {
    case missingToken
    case missingOrgId
    case invalidURL
    case unexpectedResponse
    case unauthorized
    case forbidden
    case notFound
    case http(status: Int, message: String)
    case decoding(String)
    case unknownUser

    /// Turning an HTTP response into an error is kept apart from the transport,
    /// so it can be tested without a network and without stubbing URLSession.
    static func from(status: Int, body: String) -> TrackerError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        default: return .http(status: status, message: String(body.prefix(300)))
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No OAuth token set. Open Settings."
        case .missingOrgId:
            return "No organization ID set. Open Settings."
        case .invalidURL:
            return "Malformed request URL"
        case .unexpectedResponse:
            return "Unexpected response from the server"
        case .unauthorized:
            return "401: the token is invalid or has expired"
        case .forbidden:
            return "403: access denied. Check the organization ID and its kind"
        case .notFound:
            return "404: not found"
        case let .http(status, message):
            return message.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(message)"
        case let .decoding(details):
            return "Could not parse the Tracker response: \(details)"
        case .unknownUser:
            return "Could not determine the current Tracker user"
        }
    }
}
