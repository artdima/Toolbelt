//
//  AppWindows.swift
//  Toolbelt
//
//  Все точки открытия окон собраны здесь, чтобы вью не знали друг о друге.
//

import SwiftUI

extension WindowConfiguration {
    static let weeklyReport = WindowConfiguration(
        id: "weekly-report",
        title: "Отчёт за неделю",
        size: NSSize(width: 520, height: 660)
    )
    static let issuesBoard = WindowConfiguration(
        id: "issues-board",
        title: "Мои задачи",
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
        title: "Настройки",
        size: NSSize(width: 460, height: 470),
        isResizable: false
    )
}

@MainActor
enum AppWindows {
    /// Вкладка настроек живёт дольше окна: `show(tab:)` должен переключать
    /// и уже открытое окно, поэтому роутер создаётся один раз здесь и
    /// передаётся во вью явно, а не читается ей из глобального синглтона.
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
