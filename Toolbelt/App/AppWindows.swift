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
        size: NSSize(width: 560, height: 640),
        toolbarStyle: .unified
    )
    static let issuesBoard = WindowConfiguration(
        id: "issues-board",
        title: "My Issues",
        size: NSSize(width: 960, height: 590),
        toolbarStyle: .unified
    )
    static let simulators = WindowConfiguration(
        id: "simulators",
        title: "Simulators",
        size: NSSize(width: 560, height: 660),
        toolbarStyle: .unified
    )
    static let deepLink = WindowConfiguration(
        id: "deep-link",
        title: "Deep Link",
        size: NSSize(width: 560, height: 550),
        usesEmptyToolbar: true
    )
    static let userDefaults = WindowConfiguration(
        id: "user-defaults",
        title: "User Defaults",
        size: NSSize(width: 720, height: 610),
        toolbarStyle: .unified
    )
    static let releaseNotes = WindowConfiguration(
        id: "release-notes",
        title: "Release Notes",
        size: NSSize(width: 840, height: 550),
        toolbarStyle: .unified
    )
    static let httpRequest = WindowConfiguration(
        id: "http-request",
        title: "HTTP Request",
        size: NSSize(width: 940, height: 590),
        toolbarStyle: .unified,
        usesFullSizeContent: true
    )
    static let settings = WindowConfiguration(
        id: "settings",
        title: "Settings",
        size: SettingsMetrics.paneSize,
        isResizable: false,
        toolbarStyle: .preference
    )
}

@MainActor
enum AppWindows {
    /// Weak: the window owns the controller, and opening settings "on a given section"
    /// has to switch the tab of a window that is already open.
    private static weak var settingsController: SettingsTabViewController?

    static func weeklyReport() {
        WindowPresenter.show(.weeklyReport) { WeeklyReportView() }
    }

    static func issuesBoard() {
        WindowPresenter.show(.issuesBoard) { IssuesBoardView() }
    }

    static func simulators() {
        WindowPresenter.show(.simulators) { SimulatorsView() }
    }

    static func deepLink() {
        WindowPresenter.show(.deepLink) { DeepLinkView() }
    }

    static func userDefaults() {
        WindowPresenter.show(.userDefaults) { UserDefaultsView() }
    }

    static func releaseNotes() {
        WindowPresenter.show(.releaseNotes) { ReleaseNotesView() }
    }

    static func httpRequest() {
        WindowPresenter.show(.httpRequest) { HTTPRequestView() }
    }

    static func settings(tab: SettingsTab = .profiles) {
        WindowPresenter.show(.settings, controller: {
            let controller = SettingsTabViewController()
            settingsController = controller
            return controller
        })
        settingsController?.select(tab)
    }

    static func closeSettings() {
        WindowPresenter.close(WindowConfiguration.settings.id)
    }
}
