//
//  ToolbeltApp.swift
//  Toolbelt
//

import SwiftUI

@main
struct ToolbeltApp: App {
    init() {
        // Settings have to be migrated off the old bundle id before the first
        // API call, so this runs synchronously here.
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
