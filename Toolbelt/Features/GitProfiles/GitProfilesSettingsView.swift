//
//  GitProfilesSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct GitProfilesSettingsView: View {
    private let store = GitProfileStore.shared
    private let labelWidth: CGFloat = 96

    @State private var draft: [GitProfile] = GitProfileStore.shared.profiles
    @State private var pendingDeletion: GitProfile?
    @FocusState private var focusedProfile: GitProfile.ID?

    var body: some View {
        ScrollViewReader { proxy in
            SettingsPane {
                Text("These values go into \(Text.code("git config --global user.name")) and \(Text.code("user.email")).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsMetrics.labelInset)

                if draft.isEmpty {
                    SettingsGroup {
                        Text("No profiles yet")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }

                ForEach($draft) { $profile in
                    profileSection($profile)
                        .id(profile.id)
                }

                Button {
                    addProfile(scrollingWith: proxy)
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }
        }
        .onChange(of: draft) { _, _ in
            persist()
        }
        .confirmationDialog(
            "Delete the profile “\(pendingDeletion?.title ?? "")”?",
            isPresented: isConfirmingDeletion,
            presenting: pendingDeletion
        ) { profile in
            Button("Delete", role: .destructive) { delete(profile) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Git config stays as it is until you switch to another profile.")
        }
    }

    private func profileSection(_ profile: Binding<GitProfile>) -> some View {
        let value = profile.wrappedValue

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                ProfileAvatar(initials: value.initials)
                Text(value.title.isEmpty ? "New Profile" : value.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(value.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    requestDeletion(of: value)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete profile")
            }
            .padding(.leading, 4)
            .padding(.trailing, 9)

            SettingsGroup {
                SettingsRow(labelWidth: labelWidth) {
                    Text("Name")
                        .foregroundStyle(.secondary)
                } content: {
                    TextField("Shown in the menu", text: profile.displayName)
                        .textFieldStyle(.plain)
                        .focused($focusedProfile, equals: value.id)
                }
                Divider()
                SettingsRow(labelWidth: labelWidth) {
                    Text.code("user.name")
                        .foregroundStyle(.secondary)
                } content: {
                    TextField("Your Name", text: profile.name)
                        .textFieldStyle(.plain)
                }
                Divider()
                SettingsRow(labelWidth: labelWidth) {
                    Text.code("user.email")
                        .foregroundStyle(.secondary)
                } content: {
                    TextField("you@example.com", text: profile.email)
                        .textFieldStyle(.plain)
                }
            }
        }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func addProfile(scrollingWith proxy: ScrollViewProxy) {
        let profile = GitProfile(name: "", email: "", displayName: "")
        draft.append(profile)
        // The new section has to be laid out before it can be scrolled to and focused.
        Task {
            withAnimation { proxy.scrollTo(profile.id, anchor: .bottom) }
            focusedProfile = profile.id
        }
    }

    private func requestDeletion(of profile: GitProfile) {
        // An incomplete profile was never saved, so there is nothing to lose.
        if profile.trimmed().isComplete {
            pendingDeletion = profile
        } else {
            delete(profile)
        }
    }

    private func delete(_ profile: GitProfile) {
        draft.removeAll { $0.id == profile.id }
    }

    /// Incomplete profiles stay in the form but not in the store: nothing to apply from them.
    private func persist() {
        let cleaned = draft.map { $0.trimmed() }.filter(\.isComplete)
        if cleaned != store.profiles {
            store.replace(with: cleaned)
        }
    }
}

private struct ProfileAvatar: View {
    let initials: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.1))
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
            } else {
                Text(initials)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
    }
}
