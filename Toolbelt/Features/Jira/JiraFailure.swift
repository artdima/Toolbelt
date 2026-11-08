//
//  JiraFailure.swift
//  Toolbelt
//
//  A failed Jira request as the error screen shows it.
//

import Foundation

extension TrackerFailure {
    init(jira error: Error) {
        switch error {
        case let error as JiraError:
            self = Self.jira(error)
        case let error as URLError:
            self = Self.network(error, service: "Jira")
        default:
            self = Self.unknown(error)
        }
    }

    private static func jira(_ error: JiraError) -> TrackerFailure {
        let details = error.localizedDescription

        switch error {
        case .missingSite, .missingEmail, .missingToken:
            return TrackerFailure(
                reason: "Jira credentials are incomplete.",
                suggestion: "Set the site address and an API token in Settings.",
                details: details,
                needsSettings: true
            )
        case .invalidSite:
            return TrackerFailure(
                reason: "The Jira site address is not valid.",
                suggestion: "Use an https address in Settings; plain http works only for localhost.",
                details: details,
                needsSettings: true
            )
        case .invalidURL:
            return TrackerFailure(
                reason: "Could not build the request URL.",
                suggestion: "Check the site address in Settings.",
                details: details,
                needsSettings: true
            )
        case .redirected:
            return TrackerFailure(
                reason: "Jira sent the request on to another address.",
                suggestion: "Check the site address in Settings. A sign-in page there means SSO stands in the way of the token.",
                details: details,
                needsSettings: true
            )
        case .webPage:
            return TrackerFailure(
                reason: "The address answered with a web page, not with the Jira API.",
                suggestion: "Check the site address in Settings.",
                details: details,
                needsSettings: true
            )
        case .unauthorized:
            return TrackerFailure(
                reason: "Jira did not accept the credentials.",
                suggestion: "Check them in Settings or create a fresh token.",
                details: details,
                needsSettings: true
            )
        case .forbidden:
            return TrackerFailure(
                reason: "Jira denied access.",
                suggestion: "Check the account in Settings, or sign in to Jira in the browser once.",
                details: details,
                needsSettings: true
            )
        case .notFound:
            return TrackerFailure(
                reason: "There is no Jira API at this address.",
                suggestion: "Check the site address and the deployment in Settings.",
                details: details,
                needsSettings: true
            )
        case .unknownUser:
            return TrackerFailure(
                reason: "Could not determine the current Jira user.",
                suggestion: "Check the token in Settings.",
                details: details,
                needsSettings: true
            )
        case let .http(status, _):
            return TrackerFailure(
                reason: statusReason(status),
                suggestion: suggestion(status, service: "Jira"),
                details: details
            )
        case .unexpectedResponse:
            return TrackerFailure(reason: "Jira sent an unexpected response.", suggestion: retryLater, details: details)
        case .decoding:
            return TrackerFailure(reason: "Jira sent a response the app could not read.", details: details)
        }
    }
}
