//
//  TrackerSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct TrackerSettingsView: View {
    private enum Field {
        case token
        case orgId
    }

    private let store = TrackerCredentialsStore.shared
    private let labelWidth: CGFloat = 137

    @State private var draft = TrackerCredentialsStore.shared.credentials
    @State private var isTokenVisible = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        SettingsPane {
            SettingsGroup {
                SettingsRow(labelWidth: labelWidth) {
                    Text("OAuth token")
                } content: {
                    tokenField
                }
            } footer: {
                Text("Stored in Keychain. Get one at [oauth.yandex.ru](https://oauth.yandex.ru)")
            }

            SettingsGroup {
                SettingsRow(labelWidth: labelWidth) {
                    Text("Organization ID")
                } content: {
                    TextField("123456", text: $draft.orgId)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .orgId)
                }
                Divider()
                SettingsRow(labelWidth: labelWidth) {
                    Text("Organization type")
                } content: {
                    Picker("Organization type", selection: $draft.orgKind) {
                        ForEach(TrackerOrgKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.large)
                    .fixedSize()
                }
            } footer: {
                Text("Request header: \(Text.code(draft.orgKind.headerName))")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, SettingsMetrics.labelInset)
            }
        }
        .onSubmit(commit)
        // Saved when a field is left rather than on every keystroke: each save rewrites
        // Keychain and makes the Tracker windows reload.
        .onChange(of: focusedField) { oldValue, _ in
            if oldValue != nil { commit() }
        }
        .onChange(of: draft.orgKind) { _, _ in
            commit()
        }
        .onDisappear(perform: commit)
    }

    private var tokenField: some View {
        HStack(spacing: 8) {
            Group {
                if isTokenVisible {
                    TextField("y0_Ag…", text: $draft.token)
                } else {
                    SecureField("y0_Ag…", text: $draft.token)
                }
            }
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .token)

            Button {
                isTokenVisible.toggle()
            } label: {
                Image(systemName: isTokenVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(isTokenVisible ? "Hide token" : "Show token")
        }
    }

    private func commit() {
        guard draft.trimmed() != store.credentials else { return }
        do {
            try store.save(draft)
            draft = store.credentials
            errorMessage = nil
        } catch {
            // This used to be swallowed, so the UI reported success while the token
            // was never stored.
            errorMessage = error.localizedDescription
        }
    }
}
