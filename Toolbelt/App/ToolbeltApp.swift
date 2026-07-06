//
//  ToolbeltApp.swift
//  Toolbelt
//
//  Created by Medyannik Dmitri on 08.05.2026.
//

import SwiftUI

@main
struct ToolbeltApp: App {
    init() {
        // Перенос настроек со старого bundle id должен отработать до первого
        // обращения к API, поэтому он синхронный и здесь.
        TrackerCredentialsStore.shared.migrateLegacyStorageIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "arrow.triangle.branch")
        }
        .menuBarExtraStyle(.window)
    }
}
