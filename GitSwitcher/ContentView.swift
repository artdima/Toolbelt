//
//  ContentView.swift
//  GitSwitcher
//
//  Created by Medyannik Dmitri on 08.05.2026.
//

import SwiftUI

struct GitProfile {
    let name: String
    let email: String
    let displayName: String
}

struct ContentView: View {
    @State private var statusMessage: String = ""
    @State private var activeProfile: String? = nil

    let profiles: [GitProfile] = [
        GitProfile(name: "Dmitriy Medyannik", email: "mail@artdima.ru", displayName: "Дмитрий"),
        GitProfile(name: "user2", email: "user2@example.com", displayName: "Профиль 2")
    ]

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Text("Git Switcher")
                    .font(.system(size: 15))
                    .fontWeight(.semibold)
                Spacer()
            }

            HStack(spacing: 10) {
                ForEach(profiles, id: \.displayName) { profile in
                    Button(action: {
                        applyProfile(profile)
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.displayName)
                                .font(.system(size: 14, weight: .semibold))
                            Text(profile.email)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(
                                    activeProfile == profile.displayName
                                        ? .white.opacity(0.72)
                                        : .secondary
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            activeProfile == profile.displayName
                                ? Color.accentColor.opacity(0.88)
                                : Color.white.opacity(0.07)
                        )
                        .foregroundStyle(
                            activeProfile == profile.displayName ? .white : .primary
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 8) {
                Button(action: { LLMChatWindow.show() }) {
                    actionButtonLabel(
                        title: "Спросить LLM",
                        systemImage: "sparkles",
                        tint: .secondary,
                        background: Color.white.opacity(0.07)
                    )
                }
                .buttonStyle(.plain)

                Button(action: { WeeklyReportWindow.show() }) {
                    actionButtonLabel(
                        title: "Получить отчёт за неделю",
                        systemImage: "chart.bar.doc.horizontal",
                        tint: .secondary,
                        background: Color.white.opacity(0.07)
                    )
                }
                .buttonStyle(.plain)

                Button(action: restartFork) {
                    actionButtonLabel(
                        title: "Перезапустить Fork",
                        systemImage: "arrow.counterclockwise",
                        tint: .secondary,
                        background: Color.white.opacity(0.07)
                    )
                }
                .buttonStyle(.plain)

                Button(action: captureSelectedArea) {
                    actionButtonLabel(
                        title: "Снимок выделенной области",
                        systemImage: "camera.viewfinder",
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
                .help("Завершить Git Switcher")
            }
        }
        .padding(16)
        .frame(width: 330)
        .colorScheme(.dark)
        .onAppear {
            detectCurrentProfile()
        }
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

    private func captureSelectedArea() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("Снимок экрана \(formatter.string(from: Date())).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", fileURL.path]

        process.terminationHandler = { process in
            DispatchQueue.main.async {
                withAnimation {
                    if process.terminationStatus == 0 {
                        statusMessage = "✓ Снимок сохранён в Downloads"
                    } else {
                        statusMessage = "Снимок экрана отменён"
                    }
                }
            }
        }

        do {
            try process.run()
            withAnimation { statusMessage = "Выберите область для снимка экрана" }
        } catch {
            withAnimation { statusMessage = "⚠ Не удалось запустить снимок экрана: \(error.localizedDescription)" }
        }
    }

    private func restartFork() {
        let isRunning = NSWorkspace.shared.runningApplications
            .contains(where: { $0.bundleIdentifier == "com.DanPristupov.Fork" })

        if isRunning {
            shell("pkill", "-x", "Fork")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Fork.app"))
                withAnimation { statusMessage = "↺ Fork перезапущен" }
            }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Fork.app"))
            withAnimation { statusMessage = "↺ Fork запущен" }
        }
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
                activeProfile = profile.displayName
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

        if let match = profiles.first(where: { $0.name == currentName && $0.email == currentEmail }) {
            activeProfile = match.displayName
            statusMessage = "Текущий профиль: \(match.name) <\(match.email)>"
        } else if !currentName.isEmpty {
            statusMessage = "Текущий: \(currentName) <\(currentEmail)>"
        }
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
