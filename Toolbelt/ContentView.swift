//
//  ContentView.swift
//  Toolbelt
//
//  Created by Medyannik Dmitri on 08.05.2026.
//

import SwiftUI

struct ContentView: View {
    private let store = GitProfileStore.shared
    @State private var statusMessage: String = ""
    @State private var activeProfileID: UUID? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Text("Toolbelt")
                    .font(.system(size: 15))
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { openAppWindow { AppSettingsWindow.show() } }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Настройки")
            }

            if store.profiles.isEmpty {
                Button(action: { openAppWindow { AppSettingsWindow.show(tab: .profiles) } }) {
                    actionButtonLabel(
                        title: "Добавить профиль Git",
                        systemImage: "person.crop.circle.badge.plus",
                        tint: .secondary,
                        background: Color.white.opacity(0.07)
                    )
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.profiles) { profile in
                        Button(action: { applyProfile(profile) }) {
                            profileCard(profile)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(spacing: 8) {
                Button(action: { openAppWindow { WeeklyReportWindow.show() } }) {
                    actionButtonLabel(
                        title: "Получить отчёт за неделю",
                        systemImage: "chart.bar.doc.horizontal",
                        tint: .secondary,
                        background: Color.white.opacity(0.07)
                    )
                }
                .buttonStyle(.plain)

                Button(action: { openAppWindow { IssuesBoardWindow.show() } }) {
                    actionButtonLabel(
                        title: "Мои задачи",
                        systemImage: "square.grid.3x2",
                        tint: .secondary,
                        background: Color.white.opacity(0.07)
                    )
                }
                .buttonStyle(.plain)

                Button(action: { openAppWindow { DeepLinkWindow.show() } }) {
                    actionButtonLabel(
                        title: "Deep Link",
                        systemImage: "link",
                        tint: .secondary,
                        background: Color.white.opacity(0.07)
                    )
                }
                .buttonStyle(.plain)

                Button(action: { openAppWindow { ReleaseNotesWindow.show() } }) {
                    actionButtonLabel(
                        title: "Release Notes",
                        systemImage: "doc.text",
                        tint: .secondary,
                        background: Color.white.opacity(0.07)
                    )
                }
                .buttonStyle(.plain)

                Button(action: deleteDerivedData) {
                    actionButtonLabel(
                        title: "Удалить Derived Data",
                        systemImage: "trash",
                        tint: .red,
                        background: Color.red.opacity(0.16)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: 10) {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                } else {
                    Spacer(minLength: 0)
                }

                Button(action: quitApp) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.07))
                        .foregroundStyle(.secondary)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Завершить Toolbelt")
            }
        }
        .padding(16)
        .frame(width: 330)
        .colorScheme(.dark)
        .background(MenuBarPanelReader().frame(width: 0, height: 0))
        .onAppear {
            detectCurrentProfile()
        }
        .onChange(of: store.profiles) { _, _ in
            detectCurrentProfile()
        }
    }

    /// Открывает обычное окно и закрывает меню в строке состояния,
    /// иначе панель остаётся висеть поверх открытого окна.
    private func openAppWindow(_ show: () -> Void) {
        MenuBarPanel.dismiss()
        show()
    }

    private func profileCard(_ profile: GitProfile) -> some View {
        let isActive = activeProfileID == profile.id

        return VStack(alignment: .leading, spacing: 6) {
            Text(profile.displayName.isEmpty ? profile.name : profile.displayName)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Text(profile.email)
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isActive ? .white.opacity(0.72) : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(isActive ? Color.accentColor.opacity(0.88) : Color.white.opacity(0.07))
        .foregroundStyle(isActive ? .white : .primary)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func actionButtonLabel(
        title: String,
        systemImage: String,
        tint: Color,
        background: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(background)
        .foregroundStyle(tint)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func deleteDerivedData() {
        let derivedDataURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: derivedDataURL.path) {
                try FileManager.default.removeItem(at: derivedDataURL)
                withAnimation { statusMessage = "✓ Derived Data удалена" }
            } else {
                withAnimation { statusMessage = "Derived Data уже отсутствует" }
            }
        } catch {
            withAnimation { statusMessage = "⚠ Не удалось удалить Derived Data: \(error.localizedDescription)" }
        }
    }

    private func applyProfile(_ profile: GitProfile) {
        let result = runGitConfig(name: profile.name, email: profile.email)
        withAnimation {
            if result {
                activeProfileID = profile.id
                statusMessage = "✓ Применено: \(profile.name) <\(profile.email)>"
            } else {
                statusMessage = "⚠ Не удалось применить настройки"
            }
        }
    }

    @discardableResult
    private func runGitConfig(name: String, email: String) -> Bool {
        let nameResult = shell("git", "config", "--global", "user.name", name)
        let emailResult = shell("git", "config", "--global", "user.email", email)
        return nameResult && emailResult
    }

    @discardableResult
    private func shell(_ args: String...) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func detectCurrentProfile() {
        let currentName = shellOutput("git", "config", "--global", "user.name").trimmingCharacters(in: .whitespacesAndNewlines)
        let currentEmail = shellOutput("git", "config", "--global", "user.email").trimmingCharacters(in: .whitespacesAndNewlines)

        activeProfileID = store.profiles
            .first(where: { $0.name == currentName && $0.email == currentEmail })?
            .id
    }

    private func shellOutput(_ args: String...) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

#Preview {
    ContentView()
}
