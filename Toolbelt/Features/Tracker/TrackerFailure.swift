//
//  TrackerFailure.swift
//  Toolbelt
//
//  A failed Tracker request as the error screen shows it: a sentence for people,
//  the raw text for "Technical details".
//

import Foundation

struct TrackerFailure: Equatable {
    let reason: String
    let suggestion: String?
    let details: String
    let needsSettings: Bool

    var message: String {
        [reason, suggestion].compactMap { $0 }.joined(separator: "\n")
    }

    init(reason: String, suggestion: String? = nil, details: String, needsSettings: Bool = false) {
        self.reason = reason
        self.suggestion = suggestion
        self.details = details
        self.needsSettings = needsSettings
    }

    init(_ error: Error) {
        switch error {
        case let error as TrackerError:
            self = Self.tracker(error)
        case let error as URLError:
            self = Self.network(error, service: "Tracker")
        default:
            self = Self.unknown(error)
        }
    }

    static let retryLater = "Please try again in a few moments."

    static func unknown(_ error: Error) -> TrackerFailure {
        TrackerFailure(reason: error.localizedDescription, details: String(describing: error))
    }

    private static func tracker(_ error: TrackerError) -> TrackerFailure {
        let details = error.localizedDescription

        switch error {
        case .missingToken, .missingOrgId:
            return TrackerFailure(
                reason: "Tracker credentials are incomplete.",
                suggestion: "Set an OAuth token and an organization ID in Settings.",
                details: details,
                needsSettings: true
            )
        case .unauthorized:
            return TrackerFailure(
                reason: "The OAuth token is invalid or has expired.",
                suggestion: "Paste a fresh token in Settings.",
                details: details,
                needsSettings: true
            )
        case .forbidden:
            return TrackerFailure(
                reason: "Tracker denied access.",
                suggestion: "Check the organization ID and its kind in Settings.",
                details: details,
                needsSettings: true
            )
        case .invalidURL:
            return TrackerFailure(reason: "Could not build the request URL.", details: details)
        case .unknownUser:
            return TrackerFailure(
                reason: "Could not determine the current Tracker user.",
                suggestion: "Check the OAuth token in Settings.",
                details: details,
                needsSettings: true
            )
        case .notFound:
            return TrackerFailure(reason: statusReason(404), details: details)
        case let .http(status, _):
            return TrackerFailure(
                reason: statusReason(status),
                suggestion: suggestion(status, service: "Tracker"),
                details: details
            )
        case .unexpectedResponse:
            return TrackerFailure(
                reason: "Tracker sent an unexpected response.",
                suggestion: retryLater,
                details: details
            )
        case .decoding:
            return TrackerFailure(reason: "Tracker sent a response the app could not read.", details: details)
        }
    }

    static func network(_ error: URLError, service: String) -> TrackerFailure {
        var details = "URLError \(error.code.rawValue): \(error.localizedDescription)"
        if let url = error.failingURL {
            details += "\n\(url.absoluteString)"
        }

        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return TrackerFailure(
                reason: "You appear to be offline.",
                suggestion: "Check your connection and try again.",
                details: details
            )
        case .timedOut:
            return TrackerFailure(reason: "\(service) took too long to respond.", suggestion: retryLater, details: details)
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return TrackerFailure(
                reason: "Could not reach \(service).",
                suggestion: "Check your connection or VPN and try again.",
                details: details
            )
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return TrackerFailure(
                reason: "Could not establish a secure connection to \(service).",
                suggestion: "Check your proxy or VPN settings.",
                details: details
            )
        default:
            return TrackerFailure(reason: error.localizedDescription, details: details)
        }
    }

    private static let statusPhrases: [Int: String] = [
        400: "Bad Request",
        404: "Not Found",
        408: "Request Timeout",
        409: "Conflict",
        422: "Unprocessable Content",
        429: "Too Many Requests",
        500: "Internal Server Error",
        502: "Bad Gateway",
        503: "Service Unavailable",
        504: "Gateway Timeout"
    ]

    static func statusReason(_ status: Int) -> String {
        guard let phrase = statusPhrases[status] else {
            return "The server returned HTTP \(status)."
        }
        return "The server returned \(status) \(phrase)."
    }

    static func suggestion(_ status: Int, service: String) -> String? {
        switch status {
        case 429: return "\(service) is limiting requests. Wait a minute and try again."
        case 500...599: return retryLater
        default: return nil
        }
    }
}
