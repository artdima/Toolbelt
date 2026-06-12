//
//  AppSettings.swift
//  Toolbelt
//
//  Общий экран настроек: профили Git и доступ к Яндекс Трекеру.
//

import Observation
import SwiftUI

enum SettingsTab: String, Hashable {
    case profiles
    case tracker
    case tools
}

@Observable
final class SettingsSelection {
    static let shared = SettingsSelection()

    var tab: SettingsTab = .profiles

    private init() {}
}

// MARK: - Доступ к Трекеру

@Observable
final class TrackerSettingsStore {
    static let shared = TrackerSettingsStore()

    private(set) var token: String
    private(set) var orgId: String
    private(set) var orgKind: TrackerOrgKind

    /// Растёт при каждом сохранении — окна с данными по нему перезагружаются.
    private(set) var revision = 0

    private init() {
        token = TrackerCredentials.token
        orgId = TrackerCredentials.orgId
        orgKind = TrackerCredentials.orgKind
    }

    var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespaces).isEmpty
            && !orgId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save(token newToken: String, orgId newOrgId: String, orgKind newOrgKind: TrackerOrgKind) {
        let trimmedToken = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrgId = newOrgId.trimmingCharacters(in: .whitespacesAndNewlines)

        TrackerCredentials.token = trimmedToken
        TrackerCredentials.orgId = trimmedOrgId
        TrackerCredentials.orgKind = newOrgKind

        token = trimmedToken
        orgId = trimmedOrgId
        orgKind = newOrgKind
        revision += 1
    }
}

// MARK: - Окно

enum AppSettingsWindow {
    private static var window: NSWindow?

    static func show(tab: SettingsTab = .profiles) {
        SettingsSelection.shared.tab = tab

        if let window {
            window.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let hosting = NSHostingController(rootView: SettingsView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Настройки"
        newWindow.setContentSize(NSSize(width: 460, height: 470))
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { _ in
            window = nil
            DockPresence.release()
        }

        newWindow.makeKeyAndOrderFront(nil)
        DockPresence.activate()
    }
}

// MARK: - Экран

struct SettingsView: View {
    @Bindable private var selection = SettingsSelection.shared

    var body: some View {
        TabView(selection: $selection.tab) {
            GitProfilesSettings()
                .tabItem { Label("Профили Git", systemImage: "person.2") }
                .tag(SettingsTab.profiles)

            TrackerSettings()
                .tabItem { Label("Яндекс Трекер", systemImage: "key") }
                .tag(SettingsTab.tracker)

            ToolsSettings()
                .tabItem { Label("Инструменты", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.tools)
        }
        .frame(width: 460, height: 470)
    }
}

// MARK: - Раздел «Профили Git»

struct GitProfilesSettings: View {
    private let store = GitProfileStore.shared

    @State private var draft: [GitProfile] = GitProfileStore.shared.profiles

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Значения подставляются в git config --global user.name и user.email.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if draft.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("Пока нет ни одного профиля")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($draft) { $profile in
                            profileCard($profile)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Button {
                    draft.append(GitProfile(name: "", email: "", displayName: ""))
                } label: {
                    Label("Добавить профиль", systemImage: "plus")
                }

                Spacer()

                Button("Сохранить") {
                    let cleaned = cleanedDraft()
                    store.replace(with: cleaned)
                    draft = cleaned
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cleanedDraft() == store.profiles)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func profileCard(_ profile: Binding<GitProfile>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Подпись на кнопке", text: profile.displayName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let id = profile.wrappedValue.id
                    draft.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Удалить профиль")
            }

            TextField("user.name", text: profile.name)
                .textFieldStyle(.roundedBorder)

            TextField("user.email", text: profile.email)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Пустые и незаполненные профили не сохраняем — по ним нечего применить.
    private func cleanedDraft() -> [GitProfile] {
        draft
            .map { profile in
                var trimmed = profile
                trimmed.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                trimmed.email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
                trimmed.displayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed
            }
            .filter { !$0.name.isEmpty && !$0.email.isEmpty }
    }
}

// MARK: - Раздел «Яндекс Трекер»

struct TrackerSettings: View {
    private let store = TrackerSettingsStore.shared

    @State private var token: String = TrackerSettingsStore.shared.token
    @State private var orgId: String = TrackerSettingsStore.shared.orgId
    @State private var orgKind: TrackerOrgKind = TrackerSettingsStore.shared.orgKind

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("OAuth-токен")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                SecureField("y0_Ag…", text: $token)
                    .textFieldStyle(.roundedBorder)
                Text("Хранится в Keychain. Получить: oauth.yandex.ru")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Идентификатор организации")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("123456", text: $orgId)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Тип организации")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $orgKind) {
                    ForEach(TrackerOrgKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Заголовок запроса: \(orgKind.headerName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Сохранить") {
                    store.save(token: token, orgId: orgId, orgKind: orgKind)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hasChanges: Bool {
        token.trimmingCharacters(in: .whitespacesAndNewlines) != store.token
            || orgId.trimmingCharacters(in: .whitespacesAndNewlines) != store.orgId
            || orgKind != store.orgKind
    }
}

// MARK: - Раздел «Инструменты»

struct ToolsSettings: View {
    @State private var adbPath = AndroidTools.customPath

    private var autodetected: String? { AndroidTools.autodetectedPath() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Путь к adb")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField(autodetected ?? "/path/to/platform-tools/adb", text: $adbPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                if let autodetected {
                    Text("Оставьте пустым — будет использован \(autodetected)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("adb не найден автоматически. Обычно он лежит в ~/Library/Android/sdk/platform-tools.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            Text("xcrun для симуляторов iOS берётся из /usr/bin и настройки не требует.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            HStack {
                Spacer()
                Button("Сохранить") {
                    AndroidTools.customPath = adbPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    adbPath = AndroidTools.customPath
                }
                .keyboardShortcut(.defaultAction)
                .disabled(adbPath.trimmingCharacters(in: .whitespacesAndNewlines) == AndroidTools.customPath)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    SettingsView()
}
