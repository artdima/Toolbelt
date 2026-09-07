//
//  SettingsView.swift
//  Toolbelt
//

import Observation
import SwiftUI

enum SettingsTab: String, Hashable {
    case profiles
    case tracker
    case tools
}

/// The selected tab outlives the window: opening settings "on a given section" has to
/// switch an already open window too. The instance is owned by `AppWindows`.
@Observable
@MainActor
final class SettingsRouter {
    var tab: SettingsTab = .profiles
}

struct SettingsView: View {
    @Bindable var router: SettingsRouter

    var body: some View {
        TabView(selection: $router.tab) {
            GitProfilesSettingsView()
                .tabItem { Label("Git Profiles", systemImage: "person.2") }
                .tag(SettingsTab.profiles)

            TrackerSettingsView()
                .tabItem { Label("Yandex Tracker", systemImage: "key") }
                .tag(SettingsTab.tracker)

            ToolsSettingsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.tools)
        }
        .frame(width: 460, height: 470)
    }
}

/// The bottom bar of a settings section: a save button and room for an error.
struct SettingsFooter: View {
    let errorMessage: String?
    let isSaveDisabled: Bool
    let save: () -> Void

    var body: some View {
        HStack {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
        }
    }
}
