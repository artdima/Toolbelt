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

/// Выбранная вкладка живёт дольше окна: открытие настроек «на нужном разделе»
/// должно переключать и уже открытое окно. Экземпляр создаёт `AppWindows`.
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
                .tabItem { Label("Профили Git", systemImage: "person.2") }
                .tag(SettingsTab.profiles)

            TrackerSettingsView()
                .tabItem { Label("Яндекс Трекер", systemImage: "key") }
                .tag(SettingsTab.tracker)

            ToolsSettingsView()
                .tabItem { Label("Инструменты", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.tools)
        }
        .frame(width: 460, height: 470)
    }
}

/// Нижняя панель раздела настроек: кнопка сохранения и место под ошибку.
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
            Button("Сохранить", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
        }
    }
}
