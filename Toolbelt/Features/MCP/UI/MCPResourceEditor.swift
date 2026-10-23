//
//  MCPResourceEditor.swift
//  Toolbelt
//
//  Adding a resource, checking its token, replacing its secrets, deleting the resource.
//

import Observation
import SwiftUI

enum MCPResourceEditorTarget: Identifiable {
    case add
    case edit(MCPResource)

    var id: String {
        switch self {
        case .add: "add"
        case let .edit(resource): resource.id.uuidString
        }
    }
}

@Observable
@MainActor
final class MCPResourceEditorModel {
    enum CheckState {
        case idle
        case checking
        case passed(MCPValidation, key: String)
        case failed(String)
    }

    let original: MCPResource?
    private let store: MCPResourceStore

    var kind: MCPResourceKind
    var name: String
    var address: String
    var clientID: String
    var clientSecret = ""
    var token = ""
    private(set) var check = CheckState.idle
    private(set) var saveError: String?

    convenience init(target: MCPResourceEditorTarget) {
        self.init(target: target, store: .shared)
    }

    init(target: MCPResourceEditorTarget, store: MCPResourceStore) {
        self.store = store
        switch target {
        case .add:
            original = nil
            kind = .gitlab
            name = ""
            address = MCPProviders.provider(for: .gitlab).defaultBaseURL
            clientID = ""
        case let .edit(resource):
            original = resource
            kind = resource.kind
            name = resource.name
            address = resource.baseURL.absoluteString
            clientID = resource.clientID ?? ""
        }
    }

    var isEditing: Bool { original != nil }
    var provider: any MCPProvider { MCPProviders.provider(for: kind) }
    var hint: MCPTokenHint { provider.tokenHint(for: baseURL) }

    /// A service with one address gets it from the provider; the editor does not show the field.
    var baseURL: URL? {
        provider.asksForAddress
            ? MCPResource.validatedBaseURL(address)
            : MCPResource.validatedBaseURL(provider.defaultBaseURL)
    }

    var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedClientID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedClientSecret: String { clientSecret.trimmingCharacters(in: .whitespacesAndNewlines) }

    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard provider.asksForAddress else { return kind.title }
        return baseURL.flatMap(GitLabLinkParser.host(of:)) ?? ""
    }

    var addressProblem: String? {
        guard provider.asksForAddress, !address.trimmingCharacters(in: .whitespaces).isEmpty, baseURL == nil else { return nil }
        return "Use an https:// address; plain http only works for a server on this Mac."
    }

    var nameProblem: String? {
        guard !resolvedName.isEmpty, store.isNameTaken(resolvedName, except: original?.id) else { return nil }
        return "Another resource is already called “\(resolvedName)”."
    }

    /// What the last check vouches for: a new address, token or client credential needs a new check.
    private var checkKey: String {
        [kind.rawValue, baseURL?.absoluteString ?? "", trimmedToken, storedClientID ?? "", trimmedClientSecret]
            .joined(separator: "\n")
    }

    private var storedClientID: String? {
        provider.asksForClientCredentials && !trimmedClientID.isEmpty ? trimmedClientID : nil
    }

    var passedValidation: MCPValidation? {
        guard case let .passed(validation, key) = check, key == checkKey else { return nil }
        return validation
    }

    private var keepsStoredSetup: Bool {
        guard let original else { return false }
        return trimmedToken.isEmpty
            && trimmedClientSecret.isEmpty
            && baseURL == original.baseURL
            && storedClientID == original.clientID
    }

    private var hasClientCredentials: Bool {
        guard provider.asksForClientCredentials else { return true }
        return !trimmedClientID.isEmpty && (!trimmedClientSecret.isEmpty || isEditing)
    }

    var canCheck: Bool {
        guard baseURL != nil, hasClientCredentials else { return false }
        if case .checking = check { return false }
        return !trimmedToken.isEmpty || isEditing
    }

    var canSave: Bool {
        guard baseURL != nil, !resolvedName.isEmpty, nameProblem == nil, hasClientCredentials else { return false }
        return passedValidation != nil || keepsStoredSetup
    }

    func runCheck() async {
        guard let baseURL else { return }
        let key = checkKey
        let tokenToCheck = trimmedToken.isEmpty ? original.flatMap { store.token(for: $0.id) } : trimmedToken
        guard let tokenToCheck, !tokenToCheck.isEmpty else {
            check = .failed("There is no token to check: paste one above.")
            return
        }

        var setup = MCPSetup(baseURL: baseURL, token: tokenToCheck)
        if provider.asksForClientCredentials {
            let secret = trimmedClientSecret.isEmpty ? original.flatMap { store.clientSecret(for: $0.id) } : trimmedClientSecret
            guard let secret, !secret.isEmpty else {
                check = .failed("There is no Client Secret to check with: paste it above.")
                return
            }
            setup.clientID = storedClientID
            setup.clientSecret = secret
        }

        check = .checking
        do {
            let validation = try await provider.validate(setup)
            check = .passed(validation, key: key)
        } catch {
            let secrets = [tokenToCheck, setup.clientSecret].compactMap { $0 }
            check = .failed(MCPText.redacting(secrets, in: error.localizedDescription))
        }
    }

    func save() -> Bool {
        guard canSave, let baseURL else { return false }
        let newToken = trimmedToken.isEmpty ? nil : trimmedToken
        let newClientSecret = provider.asksForClientCredentials && !trimmedClientSecret.isEmpty ? trimmedClientSecret : nil
        do {
            if var resource = original {
                resource.name = resolvedName
                resource.baseURL = baseURL
                resource.clientID = storedClientID
                if let validation = passedValidation { resource.account = validation.account }
                try store.update(resource, token: newToken, clientSecret: newClientSecret)
            } else {
                let resource = MCPResource(
                    kind: kind,
                    name: resolvedName,
                    baseURL: baseURL,
                    clientID: storedClientID,
                    account: passedValidation?.account
                )
                try store.add(resource, token: trimmedToken, clientSecret: newClientSecret)
            }
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    func delete() -> Bool {
        guard let original else { return false }
        do {
            try store.delete(original.id)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}

struct MCPResourceEditor: View {
    private enum Field {
        case name
        case address
        case clientID
        case clientSecret
        case token
    }

    @Environment(\.dismiss) private var dismiss
    @State private var model: MCPResourceEditorModel
    @State private var isTokenVisible = false
    @State private var isClientSecretVisible = false
    @State private var isConfirmingDeletion = false
    @FocusState private var focusedField: Field?

    private let labelWidth: CGFloat = 104

    init(target: MCPResourceEditorTarget) {
        _model = State(initialValue: MCPResourceEditorModel(target: target))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.isEditing ? "Edit \(model.original?.name ?? "")" : "Add Resource")
                .font(.system(size: 14, weight: .semibold))

            SettingsGroup {
                if !model.isEditing {
                    SettingsRow(labelWidth: labelWidth) {
                        Text("Type")
                    } content: {
                        Picker("Type", selection: $model.kind) {
                            ForEach(MCPResourceKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Divider()
                }
                SettingsRow(labelWidth: labelWidth) {
                    Text("Name")
                } content: {
                    TextField(model.resolvedName.isEmpty ? "work" : model.resolvedName, text: $model.name)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .name)
                }
                if model.provider.asksForAddress {
                    Divider()
                    SettingsRow(labelWidth: labelWidth) {
                        Text("Address")
                    } content: {
                        TextField(model.provider.defaultBaseURL, text: $model.address)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .address)
                    }
                }
                if model.provider.asksForClientCredentials {
                    Divider()
                    SettingsRow(labelWidth: labelWidth) {
                        Text("Client ID")
                    } content: {
                        TextField("From the app's Auth tab", text: $model.clientID)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .clientID)
                    }
                    Divider()
                    SettingsRow(labelWidth: labelWidth) {
                        Text("Client Secret")
                    } content: {
                        secretField(
                            text: $model.clientSecret,
                            placeholder: model.isEditing ? "Leave empty to keep the current secret" : "From the app's Auth tab",
                            isVisible: $isClientSecretVisible,
                            field: .clientSecret,
                            help: "secret"
                        )
                    }
                }
                Divider()
                SettingsRow(labelWidth: labelWidth) {
                    Text(model.provider.asksForClientCredentials ? "Access Token" : "Token")
                } content: {
                    secretField(
                        text: $model.token,
                        placeholder: model.isEditing ? "Leave empty to keep the current token" : model.hint.placeholder,
                        isVisible: $isTokenVisible,
                        field: .token,
                        help: "token"
                    )
                }
            } footer: {
                hintText
            }

            if let problem = model.addressProblem ?? model.nameProblem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, SettingsMetrics.labelInset)
            }

            checkResult

            if let error = model.saveError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, SettingsMetrics.labelInset)
            }

            HStack(spacing: 8) {
                HelpLink {
                    AppWindows.mcpGuide(kind: model.kind, baseURL: model.baseURL)
                }
                .help("How to set up \(model.kind.title)")
                if model.isEditing {
                    Button("Delete…", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Check") {
                    Task { await model.runCheck() }
                }
                .disabled(!model.canCheck)
                Button("Save") {
                    if model.save() { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear {
            focusedField = model.isEditing ? .token : (model.provider.asksForAddress ? .address : .name)
        }
        .confirmationDialog(
            "Delete “\(model.original?.name ?? "")”?",
            isPresented: $isConfirmingDeletion
        ) {
            Button("Delete", role: .destructive) {
                if model.delete() { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Claude loses access to it, and its secrets are erased from Keychain.")
        }
    }

    private func secretField(
        text: Binding<String>,
        placeholder: String,
        isVisible: Binding<Bool>,
        field: Field,
        help: String
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .focused($focusedField, equals: field)

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(isVisible.wrappedValue ? "Hide \(help)" : "Show \(help)")
        }
    }

    private var hintText: some View {
        let hint = model.hint
        var text = AttributedString(hint.text + " ")
        if let url = hint.url {
            var link = AttributedString(hint.linkTitle)
            link.link = url
            text += link + AttributedString(". ")
        }
        text += AttributedString("Stored in Keychain only.")
        return Text(text)
    }

    @ViewBuilder
    private var checkResult: some View {
        switch model.check {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the token…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SettingsMetrics.labelInset)
        case let .failed(message):
            NoticeBanner(systemImage: "xmark.octagon", tint: .red) {
                Text(message)
            }
        case let .passed(validation, _):
            NoticeBanner(
                systemImage: validation.warnings.isEmpty ? "checkmark.seal" : "exclamationmark.triangle",
                tint: validation.warnings.isEmpty ? .green : .orange
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.provider.accountSummary(validation.account))
                        .fontWeight(.medium)
                    Text(tokenSummary(validation.account))
                        .foregroundStyle(.secondary)
                    ForEach(validation.warnings, id: \.self) { warning in
                        Text(warning)
                    }
                    if model.passedValidation == nil {
                        Text("The setup changed after the check. Check again to save.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func tokenSummary(_ account: MCPAccount) -> String {
        var parts: [String] = []
        if let tokenName = account.tokenName { parts.append("token “\(tokenName)”") }
        if let scopes = account.scopes { parts.append("scopes: \(scopes.isEmpty ? "none" : scopes.joined(separator: ", "))") }
        parts.append(MCPViewModel.expiryText(account).text)
        return parts.joined(separator: " · ")
    }
}
