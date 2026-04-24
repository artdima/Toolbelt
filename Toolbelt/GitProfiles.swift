//
//  GitProfiles.swift
//  Toolbelt
//
//  Профили git-пользователей: хранение в UserDefaults и окно редактирования.
//

import SwiftUI

struct GitProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var displayName: String
}

final class GitProfileStore: ObservableObject {
    static let shared = GitProfileStore()

    private static let storageKey = "git.profiles"

    @Published var profiles: [GitProfile] {
        didSet { persist() }
    }

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        profiles = data.flatMap { try? JSONDecoder().decode([GitProfile].self, from: $0) } ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Окно настроек

enum GitProfilesWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let hosting = NSHostingController(rootView: GitProfilesView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Профили Git"
        newWindow.setContentSize(NSSize(width: 420, height: 440))
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
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

    static func close() {
        window?.close()
    }
}

// MARK: - Редактор

struct GitProfilesView: View {
    @ObservedObject private var store = GitProfileStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Профили Git")
                .font(.system(size: 14, weight: .semibold))

            Text("Значения подставляются в git config --global user.name и user.email.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if store.profiles.isEmpty {
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
                        ForEach($store.profiles) { $profile in
                            profileCard($profile)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Button {
                    store.profiles.append(GitProfile(name: "", email: "", displayName: ""))
                } label: {
                    Label("Добавить профиль", systemImage: "plus")
                }

                Spacer()

                Button("Готово") {
                    GitProfilesWindow.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 400, minHeight: 360)
    }

    private func profileCard(_ profile: Binding<GitProfile>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Подпись на кнопке", text: profile.displayName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let id = profile.wrappedValue.id
                    store.profiles.removeAll { $0.id == id }
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
}

#Preview {
    GitProfilesView()
}
