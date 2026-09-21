//
//  ToolsSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct ToolsSettingsView: View {
    @State private var adbPath = AndroidTools.customPath
    @State private var claudePath = ClaudeCLI.customPath
    /// Checking the paths hits the file system — do it once, not on every redraw.
    @State private var autodetectedAdbPath = AndroidTools.autodetectedPath()
    @State private var autodetectedClaudePath = ClaudeCLI.autodetectedPath()
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pathField(
                title: "Path to adb",
                placeholder: "/path/to/platform-tools/adb",
                text: $adbPath,
                autodetected: autodetectedAdbPath,
                notFoundHint: "adb was not found automatically. It usually lives in ~/Library/Android/sdk/platform-tools."
            )

            pathField(
                title: "Path to claude",
                placeholder: "/path/to/claude",
                text: $claudePath,
                autodetected: autodetectedClaudePath,
                notFoundHint: "Claude CLI was not found automatically. The native installer puts it in ~/.local/bin."
            )

            Text("xcrun for iOS simulators comes from /usr/bin and needs no configuration.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            SettingsFooter(
                errorMessage: errorMessage,
                isSaveDisabled: trimmed(adbPath) == AndroidTools.customPath
                    && trimmed(claudePath) == ClaudeCLI.customPath,
                save: save
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func pathField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        autodetected: String?,
        notFoundHint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField(autodetected ?? placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            if let autodetected {
                Text("Leave empty to use \(autodetected)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text(notFoundHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func trimmed(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        do {
            try AndroidTools.setCustomPath(trimmed(adbPath))
            try ClaudeCLI.setCustomPath(trimmed(claudePath))
            adbPath = AndroidTools.customPath
            claudePath = ClaudeCLI.customPath
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
