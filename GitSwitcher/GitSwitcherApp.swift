//
//  GitSwitcherApp.swift
//  GitSwitcher
//
//  Created by Medyannik Dmitri on 08.05.2026.
//

import SwiftUI

@main
struct GitSwitcherApp: App {
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "arrow.triangle.branch")
        }
        .menuBarExtraStyle(.window)
    }
}
