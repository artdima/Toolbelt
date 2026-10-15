//
//  MenuBarView.swift
//  Toolbelt
//
//  The app panel in the menu bar.
//

import SwiftUI

struct MenuBarView: View {
    @State private var model = MenuBarViewModel()
    @State private var isConfirmingDerivedDataCleanup = false

    var body: some View {
        VStack(spacing: 0) {
            header
            PanelDivider()
            gitProfiles
            tools
            PanelDivider()
                .padding(.vertical, 6)
            if isConfirmingDerivedDataCleanup {
                PanelConfirmation(
                    title: "Delete Derived Data?",
                    message: "Every project will have to be rebuilt from scratch.",
                    systemImage: "trash",
                    confirmTitle: "Delete",
                    onCancel: { isConfirmingDerivedDataCleanup = false },
                    onConfirm: {
                        isConfirmingDerivedDataCleanup = false
                        Task { await model.cleanDerivedData() }
                    }
                )
            } else {
                PanelRow(
                    title: "Delete Derived Data…",
                    systemImage: "trash",
                    role: .destructive,
                    isBusy: model.isWorking
                ) {
                    isConfirmingDerivedDataCleanup = true
                }
                .disabled(model.isWorking)
            }
            PanelDivider()
                .padding(.vertical, 6)
            footer
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(width: 340)
        .background(MenuBarPanelReader().frame(width: 0, height: 0))
        .task {
            await model.refreshActiveProfile()
        }
        .onChange(of: model.profiles) { _, _ in
            Task { await model.refreshActiveProfile() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(.toolbeltMark)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            Text("Toolbelt")
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 12)
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(model.status)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 15)
        .padding(.bottom, 10)
    }

    private var gitProfiles: some View {
        PanelSection("Git profile", id: "git-profile") {
            if model.profiles.isEmpty {
                PanelRow(title: "Add a Git profile…", systemImage: "plus", role: .prominent) {
                    AppWindows.settings(tab: .profiles)
                }
            } else {
                ForEach(model.profiles) { profile in
                    profileRow(profile)
                }
            }
        }
    }

    private func profileRow(_ profile: GitProfile) -> some View {
        let isActive = model.activeProfileID == profile.id

        return PanelRow(
            title: profile.title,
            systemImage: isActive ? "checkmark" : "person",
            role: isActive ? .prominent : .standard,
            detail: profile.email
        ) {
            Task { await model.apply(profile) }
        }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var tools: some View {
        PanelSection("Yandex Tracker", id: "tracker") {
            PanelRow(title: "Weekly Report", systemImage: "doc.plaintext") {
                AppWindows.weeklyReport()
            }
            PanelRow(title: "My Issues", systemImage: "square.grid.2x2") {
                AppWindows.issuesBoard()
            }
        }
        PanelSection("Xcode", id: "xcode") {
            PanelRow(title: "Simulators", systemImage: "iphone") {
                AppWindows.simulators()
            }
            PanelRow(title: "Deep Link", systemImage: "link") {
                AppWindows.deepLink()
            }
            PanelRow(title: "User Defaults", systemImage: "list.bullet.rectangle") {
                AppWindows.userDefaults()
            }
        }
        PanelSection("Utilities", id: "utilities") {
            PanelRow(title: "HTTP Request", systemImage: "globe") {
                AppWindows.httpRequest()
            }
            PanelRow(title: "Release Notes", systemImage: "doc.text") {
                AppWindows.releaseNotes()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            PanelCommand(title: "Settings…", key: ",") {
                AppWindows.settings()
            }
            PanelCommand(title: "Quit Toolbelt", key: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

#Preview {
    MenuBarView()
}
