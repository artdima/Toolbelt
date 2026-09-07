//
//  TrackerSettingsView.swift
//  Toolbelt
//

import SwiftUI

struct TrackerSettingsView: View {
    private let store = TrackerCredentialsStore.shared

    @State private var draft = TrackerCredentialsStore.shared.credentials
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(title: "OAuth token", hint: "Stored in Keychain. Get one at oauth.yandex.ru") {
                SecureField("y0_Ag…", text: $draft.token)
                    .textFieldStyle(.roundedBorder)
            }

            field(title: "Organization ID", hint: nil) {
                TextField("123456", text: $draft.orgId)
                    .textFieldStyle(.roundedBorder)
            }

            field(title: "Organization type", hint: "Request header: \(draft.orgKind.headerName)") {
                Picker("", selection: $draft.orgKind) {
                    ForEach(TrackerOrgKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Spacer()

            SettingsFooter(
                errorMessage: errorMessage,
                isSaveDisabled: draft.trimmed() == store.credentials,
                save: save
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func field<Content: View>(
        title: String,
        hint: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func save() {
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
