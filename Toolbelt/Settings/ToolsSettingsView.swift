//
//  ToolsSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct ToolsSettingsView: View {
    @State private var adbPath = AndroidTools.customPath
    /// Проверка путей ходит в файловую систему — считаем один раз, а не на каждый рендер.
    @State private var autodetectedPath = AndroidTools.autodetectedPath()
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Путь к adb")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField(autodetectedPath ?? "/path/to/platform-tools/adb", text: $adbPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                if let autodetectedPath {
                    Text("Оставьте пустым — будет использован \(autodetectedPath)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("adb не найден автоматически. Обычно он лежит в ~/Library/Android/sdk/platform-tools.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            Text("xcrun для симуляторов iOS берётся из /usr/bin и настройки не требует.")
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
