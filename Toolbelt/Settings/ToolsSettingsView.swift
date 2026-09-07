//
//  ToolsSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct ToolsSettingsView: View {
    @State private var adbPath = AndroidTools.customPath
    /// Checking the paths hits the file system — do it once, not on every redraw.
    @State private var autodetectedPath = AndroidTools.autodetectedPath()
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Path to adb")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField(autodetectedPath ?? "/path/to/platform-tools/adb", text: $adbPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                if let autodetectedPath {
                    Text("Leave empty to use \(autodetectedPath)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("adb was not found automatically. It usually lives in ~/Library/Android/sdk/platform-tools.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            Text("xcrun for iOS simulators comes from /usr/bin and needs no configuration.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            SettingsFooter(
                errorMessage: errorMessage,
                isSaveDisabled: trimmedPath == AndroidTools.customPath,
                save: save
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var trimmedPath: String {
        adbPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        do {
            try AndroidTools.setCustomPath(trimmedPath)
            adbPath = AndroidTools.customPath
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
