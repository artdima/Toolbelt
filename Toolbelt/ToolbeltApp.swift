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
        TrackerCredentials.migrateLegacyStorageIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "arrow.triangle.branch")
        }
        .menuBarExtraStyle(.window)
    }
}
