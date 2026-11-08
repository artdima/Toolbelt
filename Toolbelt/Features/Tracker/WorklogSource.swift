//
//  WorklogSource.swift
//  Toolbelt
//
//  Where the weekly report takes logged time from.
//

import Foundation

protocol WorklogService {
    var isConfigured: Bool { get }
    /// Changes with the settings, so an open report reloads.
    var settingsRevision: AnyHashable { get }
    func worklog(from: Date, to: Date) async throws -> [Worklog]
}

enum WorklogSource: String {
    case tracker
    case jira

    var title: String {
        switch self {
        case .tracker: return "Yandex Tracker"
        case .jira: return "Jira"
        }
    }

    var settingsTab: SettingsTab {
        switch self {
        case .tracker: return .tracker
        case .jira: return .jira
        }
    }

    var setupText: String {
        switch self {
        case .tracker: return "Set an OAuth token and an organization ID\nto pull the report from Yandex Tracker"
        case .jira: return "Set the site address and an API token\nto pull the report from Jira"
        }
    }

    var loadingText: String {
        switch self {
        case .tracker: return "Loading entries from Tracker…"
        case .jira: return "Loading entries from Jira…"
        }
    }

    func makeService() -> WorklogService {
        switch self {
        case .tracker: return TrackerClient()
        case .jira: return JiraClient()
        }
    }

    func failure(for error: Error) -> TrackerFailure {
        switch self {
        case .tracker: return TrackerFailure(error)
        case .jira: return TrackerFailure(jira: error)
        }
    }
}
