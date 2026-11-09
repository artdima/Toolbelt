//
//  UpdatesSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct UpdatesSettingsView: View {
    @Bindable private var updater = AppUpdater.shared

    var body: some View {
        SettingsPane {
            SettingsGroup {
                HStack(spacing: 10) {
                    Text("Toolbelt \(updater.currentVersion)")
                        .font(.system(size: 13))
                    Spacer(minLength: 8)
                    Button("Check Now") { updater.checkForUpdates() }
                        .buttonBorderShape(.capsule)
                        .disabled(!updater.canCheckForUpdates)
                }
                .padding(.leading, 10)
                .padding(.trailing, 5)
                .frame(minHeight: 34)
            } footer: {
                Text("Updates come from the releases of \(Text.code("artdima/Toolbelt")) on GitHub. One is installed only if it is signed with the key built into Toolbelt.")
            }

            SettingsGroup {
                SwitchRow(title: "Check for updates daily", isOn: $updater.automaticallyChecksForUpdates)
                Divider()
                SwitchRow(title: "Download updates in the background", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
            } footer: {
                Text("A downloaded update installs when you quit Toolbelt, or at once from Restart to Update in the menu bar. Toolbelt does not restart by itself: that would drop Claude's MCP connection.")
            }
        }
    }
}

private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? .primary : .secondary)
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
    }
}
