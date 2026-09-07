//
//  AppWindows.swift
//  Toolbelt
//
//  Every entry point that opens a window lives here, so views never reference
//  one another.
//

import SwiftUI

extension WindowConfiguration {
    static let weeklyReport = WindowConfiguration(
        id: "weekly-report",
        title: "Weekly Report",
        size: NSSize(width: 520, height: 660)
    )
    static let issuesBoard = WindowConfiguration(
        id: "issues-board",
        title: "My Issues",
        size: NSSize(width: 980, height: 640)
    )
    static let deepLink = WindowConfiguration(
        id: "deep-link",
        title: "Deep Link",
        size: NSSize(width: 560, height: 560)
    )
    static let releaseNotes = WindowConfiguration(
        id: "release-notes",
        title: "Release Notes",
        size: NSSize(width: 620, height: 680)
    )
    static let settings = WindowConfiguration(
        id: "settings",
        title: "Settings",
        size: NSSize(width: 460, height: 470),
        isResizable: false
    )
}

@MainActor
enum AppWindows {
    /// The selected tab outlives the window: opening settings "on a given section"
    /// has to switch an already open window too. The router is created once here and
    /// handed to the view explicitly instead of being read from a global singleton.
    private static let settingsRouter = SettingsRouter()

    static func weeklyReport() {
        WindowPresenter.show(.weeklyReport) { WeeklyReportView() }
    }

    static func issuesBoard() {
        WindowPresenter.show(.issuesBoard) { IssuesBoardView() }
    }

    static func deepLink() {
        WindowPresenter.show(.deepLink) { DeepLinkView() }
    }

    static func releaseNotes() {
        WindowPresenter.show(.releaseNotes) { ReleaseNotesView() }
    }

    static func settings(tab: SettingsTab = .profiles) {
        settingsRouter.tab = tab
        WindowPresenter.show(.settings) { SettingsView(router: settingsRouter) }
    }

    static func closeSettings() {
        WindowPresenter.close(WindowConfiguration.settings.id)
    }
}
