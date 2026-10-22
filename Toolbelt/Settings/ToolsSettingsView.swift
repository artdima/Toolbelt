//
//  ToolsSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct ToolsSettingsView: View {
    /// Checking the paths hits the file system — do it once, not on every redraw.
    @State private var autodetectedAdbPath = AndroidTools.autodetectedPath()
    @State private var autodetectedClaudePath = ClaudeCLI.autodetectedPath()

    var body: some View {
        SettingsPane {
            PathSetting(
                title: "Path to adb",
                placeholder: "/path/to/platform-tools/adb",
                autodetected: autodetectedAdbPath,
                notFoundHint: "adb was not found automatically. It usually lives in ~/Library/Android/sdk/platform-tools.",
                current: AndroidTools.customPath
            ) { path in
                try AndroidTools.setCustomPath(path)
                return AndroidTools.customPath
            }

            PathSetting(
                title: "Path to claude",
                placeholder: "/path/to/claude",
                autodetected: autodetectedClaudePath,
                notFoundHint: "Claude CLI was not found automatically. The native installer puts it in ~/.local/bin.",
                current: ClaudeCLI.customPath
            ) { path in
                try ClaudeCLI.setCustomPath(path)
                return ClaudeCLI.customPath
            }

            NoticeBanner(systemImage: "info.circle", tint: .gray, message: {
                Text("\(Text.code("xcrun")) for iOS simulators comes from \(Text.code("/usr/bin")) and needs no configuration. The Android emulator is taken from the same SDK as adb.")
                    .foregroundStyle(.secondary)
            })
        }
    }
}

/// A path to a command-line tool: typed in or picked in Finder, saved as soon as it is
/// committed, since the path is validated against an allowlist only on save.
private struct PathSetting: View {
    let title: String
    let placeholder: String
    let autodetected: String?
    let notFoundHint: String
    /// Saves the path and returns what was actually stored (a standardized path).
    let save: @MainActor (String) throws -> String

    @State private var text: String
    @State private var savedPath: String
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init(
        title: String,
        placeholder: String,
        autodetected: String?,
        notFoundHint: String,
        current: String,
        save: @escaping @MainActor (String) throws -> String
    ) {
        self.title = title
        self.placeholder = placeholder
        self.autodetected = autodetected
        self.notFoundHint = notFoundHint
        self.save = save
        _text = State(initialValue: current)
        _savedPath = State(initialValue: current)
    }

    var body: some View {
        SettingsGroup(title) {
            HStack(spacing: 10) {
                TextField(autodetected ?? placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($isFocused)
                    .onSubmit(commit)

                if !text.isEmpty {
                    Button {
                        text = ""
                        commit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(autodetected == nil ? "Clear" : "Use the detected path")
                }

                Button("Choose…", action: choose)
                    .buttonBorderShape(.capsule)
            }
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .frame(minHeight: 34)
        } footer: {
            footer
        }
        .onChange(of: isFocused) { wasFocused, _ in
            if wasFocused { commit() }
        }
        .onDisappear(perform: commit)
    }

    @ViewBuilder
    private var footer: some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
        } else if let autodetected {
            Text("Leave empty to use \(Text.code(autodetected))")
        } else {
            Text(notFoundHint)
                .foregroundStyle(.orange)
        }
    }

    private func commit() {
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path != savedPath else {
            errorMessage = nil
            return
        }
        do {
            savedPath = try save(path)
            text = savedPath
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(title.replacingOccurrences(of: "Path to ", with: ""))"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // ~/.local/bin, where Claude CLI lives, is hidden.
        panel.showsHiddenFiles = true
        if let directory = [text, autodetected ?? ""].first(where: { !$0.isEmpty }) {
            panel.directoryURL = URL(fileURLWithPath: directory).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        text = url.path
        commit()
    }
}
