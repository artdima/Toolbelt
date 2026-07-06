//
//  GitProfilesSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct GitProfilesSettingsView: View {
    private let store = GitProfileStore.shared

    @State private var draft: [GitProfile] = GitProfileStore.shared.profiles

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Значения подставляются в git config --global user.name и user.email.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if draft.isEmpty {
                EmptyState(
                    systemImage: "person.crop.circle.badge.plus",
                    text: "Пока нет ни одного профиля"
                )
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
                    let cleaned = cleanedDraft
                    store.replace(with: cleaned)
                    draft = cleaned
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cleanedDraft == store.profiles)
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

    /// Незаполненные профили не сохраняем — по ним нечего применить.
    private var cleanedDraft: [GitProfile] {
        draft.map { $0.trimmed() }.filter(\.isComplete)
    }
}
