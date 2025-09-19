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
        VStack(spacing: 24) {
            HStack(spacing: 2) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Git Switcher")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            HStack(spacing: 16) {
                ForEach(profiles, id: \.displayName) { profile in
                    Button(action: {
                        applyProfile(profile)
                    }) {
                        VStack(spacing: 6) {
                            Text(profile.displayName)
                                .font(.headline)
                            Text(profile.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            activeProfile == profile.displayName
                                ? Color.accentColor
                                : Color.secondary.opacity(0.12)
                        )
                        .foregroundStyle(
                            activeProfile == profile.displayName ? .white : .primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(28)
        .frame(width: 380)
        .onAppear {
            detectCurrentProfile()
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
