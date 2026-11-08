//
//  JiraSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct JiraSettingsView: View {
    private enum Field {
        case site
        case email
        case token
    }

    private let store = JiraCredentialsStore.shared
    private let labelWidth: CGFloat = 137

    @State private var draft = JiraCredentialsStore.shared.credentials
    @State private var isTokenVisible = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        SettingsPane {
            SettingsGroup {
                SettingsRow(labelWidth: labelWidth) {
                    Text("Deployment")
                } content: {
                    PillPicker(selection: $draft.deployment, options: JiraDeployment.allCases) { $0.title }
                }
                Divider()
                SettingsRow(labelWidth: labelWidth) {
                    Text("Site address")
                } content: {
                    TextField(draft.needsEmail ? "company.atlassian.net" : "jira.company.com", text: $draft.site)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .site)
                }
            } footer: {
                siteFooter
            }

            SettingsGroup {
                if draft.needsEmail {
                    SettingsRow(labelWidth: labelWidth) {
                        Text("Email")
                    } content: {
                        TextField("name@company.com", text: $draft.email)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .email)
                    }
                    Divider()
                }
                SettingsRow(labelWidth: labelWidth) {
                    Text(draft.needsEmail ? "API token" : "Access token")
                } content: {
                    tokenField
                }
            } footer: {
                tokenFooter
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, SettingsMetrics.labelInset)
            }
        }
        .onSubmit(commit)
        .onChange(of: focusedField) { oldValue, _ in
            if oldValue != nil { commit() }
        }
        .onChange(of: draft.deployment) { _, _ in
            commit()
        }
        .onDisappear(perform: commit)
    }

    @ViewBuilder
    private var siteFooter: some View {
        if let url = draft.siteURL {
            Text("Requests go to \(Text.code(url.absoluteString + "/rest/api/2"))")
        } else if draft.site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("The address Jira opens at in the browser")
        } else {
            Text("Not an https address. Plain http works only for localhost.")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var tokenFooter: some View {
        if draft.needsEmail {
            Text("Stored in Keychain. Create one without scopes at [id.atlassian.com](https://id.atlassian.com/manage-profile/security/api-tokens)")
        } else {
            Text("Stored in Keychain. Create one in Jira: your profile → Personal Access Tokens")
        }
    }

    private var tokenField: some View {
        HStack(spacing: 8) {
            Group {
                if isTokenVisible {
                    TextField("Paste the token", text: $draft.token)
                } else {
                    SecureField("Paste the token", text: $draft.token)
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
            errorMessage = error.localizedDescription
        }
    }
}
